module Qops::DeployHelpers
  private

  def config
    return @_config if @_config

    Qops::Environment.notifiers

    @_config ||= Qops::Environment.new
    fail "Invalid configure deploy_type detected: #{@_config.deploy_type}" unless [:staging, :production].include?(@_config.deploy_type)
    @_config
  end

  def custom_json
    return @_custom_json if @_custom_json

    @_custom_json = {
        deploy: {
            config.app_name => {
                scm: {
                    revision: config.revision
                }
            }
        }
    }

    unless ENV['DEPLOY_JSON'].blank?
      your_json = JSON.parse(ENV['DEPLOY_JSON'])
      @_custom_json[:deploy][config.app_name].merge!(your_json)
      puts "Using custom json:\n#{JSON.pretty_generate(@_custom_json)}"
    end

    @_custom_json
  end

  def iterator(options)
    config.wait_iterations.times.each do |i|
      result = yield(i)
      break if result

      if i + 1 == config.wait_iterations
        puts " failed to complete within #{config.wait_iterations} seconds"
        ping_slack(Quandl::Slack::Release, 'Command timeout', 'failure',
                   options.merge(failed_at: Time.now)
                  )
        exit(-1)
      else
        print " #{i / 60} minute(s) " if been_a_minute?(i)
      end

      sleep(1)
    end
  end

  def retrieve_instances
    # Describe and create instances as necessary
    instances_results = config.opsworks.describe_instances(layer_id: config.layer_id)

    # Determine if instance exists.
    instances_results.data.instances
  end

  def retrieve_instance
    # Describe and create instances as necessary
    instances_results = config.opsworks.describe_instances(layer_id: config.layer_id)

    # Determine if instance exists.
    instances = instances_results.data.instances

    return unless instances.map(&:hostname).include?(requested_hostname)

    instances.find { |k| k.hostname == requested_hostname }
  end

  def been_a_minute?(i)
    i > 1 && i % 60 == 0
  end

  def run_opsworks_command(deployment_params, instance_ids = [])
    deployment_params[:instance_ids] = instance_ids unless instance_ids.empty?

    # Create the deployment
    deployment_results = config.opsworks.create_deployment(deployment_params)
    deployment_id = deployment_results.data.deployment_id

    iterator(deployment_params) do |i|
      deployment_results = config.opsworks.describe_deployments(deployment_ids: [deployment_id])
      deployment = deployment_results.data.deployments.first

      if deployment.completed_at
        puts ' ' + deployment.status

        if deployment.status != 'successful'
          read_failure_log(deployment_id: deployment.deployment_id)
          exit(-1)
        end

        true
      else
        print '.'
        if been_a_minute?(i)
          print " #{retrieve_instance.status} :" if config.deploy_type == :staging
          print " #{deployment.status} :" if config.deploy_type == :production
        end
      end
    end

    print "\n"
  end

  def read_failure_log(opsworks_options, options = {})
    commands = config.opsworks.describe_commands(opsworks_options)
    commands.data.each do |results|
      results.each do |command|
        if command.log_url
          puts "\nReading last 100 lines from #{command.log_url}\n"
          lines = open(command.log_url).read.split("\n")
          num_lines = lines.count < config.command_log_lines ? lines.count : config.command_log_lines
          puts open(command.log_url).read.split("\n")[-1 * num_lines..-1].join("\n")
          puts "\nLog file at: #{command.log_url}"
        end

        ping_slack(Quandl::Slack::Release, 'Deployment failure', 'failure',
            (options[:manifest] || {}).merge(
                command: command.type,
                status: command.status
            )
        )

        if options[:last_only]
          exit(-1)
        end
      end
    end
  end

  def requested_hostname
    return @requested_hostname if @requested_hostname
    if config.deploy_type == :staging
      @requested_hostname = "#{config.app_name}-#{config.deploy_type}-#{config.revision.parameterize}"
    elsif config.deploy_type == :production
      @requested_hostname = "#{config.app_name}-#{config.revision.parameterize}"
      existing_hostnames = retrieve_instances.map(&:hostname)
      @requested_hostname += "-#{existing_hostnames.last.to_s.split('-').last.to_i + 1}"
    end

    @requested_hostname = @requested_hostname[0..62]
  end

  def ping_slack(notifier, message, status, manifest)
    fields = manifest.keys
    fields.map! { |field| { title: field, value: manifest[field], short: true } }
    notifier.ping("#{config.app_name}: #{message}",
                  attachments: [{ color: status, mrkdwn_in: ['text'], fallback: 'Details', fields: fields }]
                 )
  end
end
