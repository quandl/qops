class Qops::Deploy < Thor
  include Qops::DeployHelpers

  class_option :custom_json, type: :string, aliases: '-j', desc: 'A custom json that will be used during a deployment of the app. ex: \'{ "custom_attrs": "are awesome!"}\''

  desc 'app', 'Deploy the latest version of the app'
  def app
    initialize_run

    instances = if config.deploy_type == 'staging'
                  [retrieve_instance].compact
                else
                  retrieve_instances
                end
    online_instances = instances.select { |instance| instance.status == 'online' }

    if online_instances.count == 0
      raise 'Could not find any running instance(s) to deploy to. Perhaps you need to run "qops:instance:up" first'
    end

    if config.deploy_type == 'staging'
      puts "Preparing to deploy branch #{default_revision} to instance #{online_instances.first.hostname}"
    else
      puts "Preparing to deploy default branch to all (online) servers (#{online_instances.map(&:hostname).join(', ')})"
    end

    base_deployment_params = {
      stack_id: config.stack_id,
      command: { name: 'deploy' }
    }

    if !config.application_id
      Qops::Environment.print_with_colour('No application specified. Exiting without application deployment.')
      exit(0)
    else
      base_deployment_params[:app_id] = config.application_id
    end

    if config.deploy_type != 'production'
      base_deployment_params[:custom_json] = custom_json.to_json
    end

    manifest = { environment: config.deploy_type }

    # Deploy the first instance with migration on
    first_instance = online_instances.first
    print "Migrating and deploying first instance (#{first_instance.hostname}) ..."
    deployment_params = base_deployment_params.deep_dup
    should_migrate = !config.option?(:migrate) || config.option?(:migrate) && config.migrate == true
    deployment_params[:command][:args] = { migrate: ['true'] } if should_migrate
    run_opsworks_command(deployment_params, [first_instance.instance_id])
    ping_slack(
      'Quandl::Slack::Release',
      "Deployed and migrated instance '#{first_instance.hostname}'",
      'success',
      manifest.merge(
        app_name: config.app_name,
        command: 'deploy + migrate',
        migrate: should_migrate.to_s,
        completed: Time.now,
        hostname: first_instance.hostname,
        instance_id: first_instance.instance_id
      )
    )

    # Deploy any remaining instances with migration off for production
    return unless config.deploy_type == 'production' && online_instances.count > 1

    print 'Deploying remaining instances ...'
    deployment_params = base_deployment_params.deep_dup
    run_opsworks_command(deployment_params)
    ping_slack(
      'Quandl::Slack::Release',
      'Deployed All Instances',
      'success',
      manifest.merge(
        app_name: config.app_name,
        command: 'deploy',
        migrate: false,
        completed: Time.now,
        hostname: online_instances.map(&:hostname),
        instance_id: online_instances.map(&:instance_id)
      )
    )
  end

  private

  def custom_json
    return @_custom_json if @_custom_json

    @_custom_json = {}

    if config.application_id
      application_name = config.opsworks.describe_apps(app_ids: [config.application_id]).apps.first.name

      @_custom_json[:deploy] = {
        application_name => {
          scm: {
            revision: default_revision
          }
        }
      }
    end

    if options[:custom_json].present?
      your_json = JSON.parse(options[:custom_json])
      @_custom_json.merge!(your_json)
      puts "Using custom json:\n#{JSON.pretty_generate(@_custom_json)}"
    end

    @_custom_json
  rescue JSON::ParserError
    say('Your custom json has invalid syntax. Failing ...', :red)
    exit(-1)
  end
end
