# frozen_string_literal: true

class Qops::Instance < Thor # rubocop:disable Metrics/ClassLength
  include Qops::DeployHelpers

  desc 'up', 'Deploy the current branch to new or existing instance(s)'
  def up
    initialize_run

    # Get the instance(s) to work with if they exist. In production we always create a new instacne
    instance = retrieve_instance if config.deploy_type == 'staging'

    # Create the instance if necessary
    if instance
      instance_id = instance.instance_id
      puts "Existing instance #{requested_hostname}"
    else
      params = {
        stack_id: config.stack_id,
        layer_ids: [config.layer_id],
        instance_type: config.instance_type,
        os: config.opsworks_os,
        hostname: requested_hostname,
        subnet_id: config.subnet,
        auto_scaling_type: config.autoscale_type,
        architecture: 'x86_64',
        root_device_type: 'ebs',
        block_device_mappings: [
          {
            device_name: 'ROOT_DEVICE',
            ebs: {
              volume_size: config.root_volume_size,
              volume_type: 'gp2',
              delete_on_termination: true
            }
          }
        ],
        ebs_optimized: config.ebs_optimize
      }
      puts 'Creating instance with params: ' + params.inspect
      instance_id = config.opsworks.create_instance(params).data.instance_id
      creating_instance = true
    end

    instance_results = config.opsworks.describe_instances(instance_ids: [instance_id])
    instance = instance_results.data.instances.first

    # Set up the automatic boot scheduler
    if config.autoscale_type == 'timer'
      print 'Setting up weekly schedule ...'
      config.opsworks.set_time_based_auto_scaling(instance_id: instance_id, auto_scaling_schedule: config.schedule)
      print "done\n"
    end

    # Record the initial instance before doing anything.
    initial_instance_state = instance

    # Start the instance if necessary
    print 'Booting instance ...'
    config.opsworks.start_instance(instance_id: instance_id) unless %w[online booting].include?(instance.status)

    manifest = {
      environment: config.deploy_type,
      app_name: config.app_name,
      command: 'add instance'
    }

    # Boot the instance
    iterator(manifest) do |i|
      instance_results = config.opsworks.describe_instances(instance_ids: [instance_id])
      instance = instance_results.data.instances.first

      if %w[booting requested pending].include?(instance.status)
        print '.'
        print " #{instance.status} :" if been_a_minute?(i)
      else
        puts ' ' + instance.status
        true
      end
    end

    puts "Public IP: #{instance.public_ip}"
    puts "Private IP: #{instance.private_ip}"

    tag_instance(instance)
    setup_instance(instance, initial_instance_state, manifest)

    if creating_instance
      ping_slack(
        'Quandl::Slack::InstanceUp',
        'Created another instance',
        'success',
        manifest.merge(
          completed: Time.now,
          hostname: instance.hostname,
          instance_id: instance.instance_id,
          private_ip: instance.private_ip,
          public_ip: instance.public_ip.blank? ? 'N/A' : instance.public_ip
        )
      )
    end

    # For Elasticsearch cluster, register with public elb
    if config.option?(:public_search_elb)
      print "Register instance #{instance.ec2_instance_id} to elb #{config.public_search_elb}"
      config.elb.register_instances_with_load_balancer(load_balancer_name: config.public_search_elb.to_s,
                                                       instances: [{ instance_id: instance.ec2_instance_id.to_s }])
    end

    # Deploy the latest code to instance
    Qops::Deploy.new([], options).app
  end

  desc 'down', 'Remove the instance associated with the given branch'
  def down
    initialize_run

    # Get the instance to shutdown
    if config.deploy_type == 'staging'
      instance = retrieve_instance
    elsif config.deploy_type == 'production'
      instance = retrieve_instances.first
    end

    if instance.nil?
      puts 'No instance available to shutdown'
      exit(0)
    else
      instance_id = instance.instance_id
    end

    terminate_instance(instance_id)

    puts 'Success'
  end

  desc 'rebuild', 'Runs the down then up command to rebuild an instance.'
  def rebuild
    down
    up
  end

  desc 'clean', 'Cleans up old instances in staging type environments'
  def clean
    initialize_run

    fail "Cannot clean instances in a #{config.deploy_type} environment" if config.deploy_type == 'production'

    terminated_instances = []

    # Find all instances to be destroyed
    retrieve_instances.each do |instance|
      next if instance.hostname == "#{config.hostname_prefix}master"

      ec2instances = config.ec2.describe_instances(instance_ids: [instance.ec2_instance_id])
      next if ec2instances.reservations.empty?

      # Get various tag values
      ec2instance = ec2instances.reservations.first.instances.first
      environment = ec2instance.tags.find { |t| t.key == 'environment' }
      cleanable = ec2instance.tags.find { |t| t.key == 'cleanable' }
      branch = ec2instance.tags.find { |t| t.key == 'branch' }

      next if !cleanable || cleanable.value != 'true'
      next if !environment || environment.value != 'staging'
      next if !branch || branch.value == 'master'

      # Find the latest command since the instance was deployed
      latest_command = Time.parse(instance.created_at)
      config.opsworks.describe_commands(instance_id: instance.instance_id).commands.each do |command|
        next if config.clean_commands_to_ignore.include?(command.type)
        completed_at = Time.parse(command.completed_at || command.acknowledged_at || command.created_at)
        latest_command = completed_at if completed_at > latest_command
      end

      # If the latest deployment is greater than the maximum alive time allowed remove the instance.
      if Time.now.to_i - latest_command.to_i > config.max_instance_duration
        terminate_instance(instance.instance_id)
        terminated_instances << instance
      end
    end

    if terminated_instances.any?
      puts "Terminated instances: #{terminated_instances.map(&:hostname).join("\n")}"
    else
      puts 'No unused instances old enough to terminate.'
    end
  end

  desc 'run_command', 'Run command on existing instance(s) at once or each one by one'
  def run_command
    initialize_run
    instances = retrieve_instances

    puts "Preparing to run command to all servers (#{instances.map(&:hostname).join(', ')})"

    command = ask('Which command you want to execute?', limited_to: %w[setup configure install_dependencies update_dependencies execute_recipes])

    option = ask('Which command you want to execute?', limited_to: %w[current all_in_once one_by_one])

    recipes = ask('Recipes list?') if command == 'execute_recipes'

    base_deployment_params = {
      stack_id: config.stack_id,
      command: {
        name: command.to_s,
        args: {
          recipes: ['wikiposit::_rebuild_elasticsearch_index']
        }
      }
    }

    manifest = { environment: config.deploy_type }

    case option
    when 'current'
      print "Run command #{command} on all instances at once ..."
      deployment_params = base_deployment_params.deep_dup
      run_opsworks_command(deployment_params)
      ping_slack(
        'Quandl::Slack::Release',
        "Run command: `#{command}` on all instances",
        'success',
        manifest.merge(
          app_name: config.app_name,
          command: 'deploy',
          migrate: false,
          completed: Time.now,
          hostname: instances.map(&:hostname),
          instance_id: instances.map(&:instance_id)
        )
      )
    when 'all_in_once'
      print "Run command #{command} on all instances at once ..."
      deployment_params = base_deployment_params.deep_dup
      run_opsworks_command(deployment_params)
      ping_slack(
        'Quandl::Slack::Release',
        "Run command: `#{command}` on all instances",
        'success',
        manifest.merge(
          app_name: config.app_name,
          command: 'deploy',
          migrate: false,
          completed: Time.now,
          hostname: instances.map(&:hostname),
          instance_id: instances.map(&:instance_id)
        )
      )
    else
      instances.each do |instance|
        print "Run command #{command} on instance #{instance.ec2_instance_id}"

        run_opsworks_command(base_deployment_params, [instance.instance_id])

        ping_slack('Quandl::Slack::InstanceDown', "Run command: `#{command}` on existing instance", 'success',
                   manifest.merge(
                     completed: Time.now,
                     hostname: instance.hostname,
                     instance_id: instance.instance_id,
                     private_ip: instance.private_ip,
                     public_ip: instance.public_ip
                   ))
        puts 'Success'
        break if instance.instance_id == instances.last.instance_id
        delay = config.wait_deploy
        puts "wait for #{delay / 60.0} mintues"
        sleep delay
      end
    end
  end

  private

  def setup_instance(instance, initial_instance_state, manifest)
    print 'Setup instance ...'

    # If the previous instance setup failed then run the setup task again when trying to bring up the instance.
    if initial_instance_state.status == 'setup_failed'
      run_opsworks_command(
        {
          stack_id: config.stack_id,
          command: {
            name: 'setup'
          }
        },
        [instance.instance_id]
      )

    # Monitor the existing instance setup.
    else
      iterator(manifest) do |i|
        instance_results = config.opsworks.describe_instances(instance_ids: [instance.instance_id])
        instance = instance_results.data.instances.first

        if %w[online].include?(instance.status)
          puts ' ' + instance.status
          true
        elsif %w[setup_failed].include?(instance.status)
          puts ' ' + instance.status
          read_failure_log(
            { instance_id: instance.instance_id },
            last_only: true,
            manifest: manifest.merge(
              hostname: instance.hostname,
              instance_id: instance.instance_id,
              private_ip: instance.private_ip,
              public_ip: instance.public_ip
            )
          )
          exit(-1)
        else
          print '.'
          print " #{instance.status} :" if been_a_minute?(i)
        end
      end
    end
  end

  def terminate_instance(instance_id)
    # Remove schedule if time based instance
    config.opsworks.set_time_based_auto_scaling(instance_id: instance_id, auto_scaling_schedule: {}) if config.autoscale_type == 'timer'

    # Get the instance from the id
    instance = retrieve_instance(instance_id)

    # For Elasticsearch cluster, remove from from public elb
    if config.option?(:public_search_elb)
      config.elb.deregister_instances_from_load_balancer(
        load_balancer_name: config.public_search_elb.to_s,
        instances: [{ instance_id: instance.ec2_instance_id.to_s }]
      )
    end

    # Attempt to shutdown the instance
    print "Attempting instance #{instance_id} - #{instance.hostname} shutdown ..."
    config.opsworks.stop_instance(instance_id: instance_id) unless instance.status == 'stopped'

    manifest = {
      environment: config.deploy_type,
      app_name: config.app_name,
      command: 'remove instance'
    }

    iterator(manifest) do |i|
      instance_results = config.opsworks.describe_instances(instance_ids: [instance_id])
      instance = instance_results.data.instances.first

      if instance.status == 'stopped'
        puts ' ' + instance.status
        true
      else
        print '.'
        print " #{instance.status} :" if been_a_minute?(i)
      end
    end

    # Terminate the instance
    puts "Terminating instance #{instance_id}"
    config.opsworks.delete_instance(instance_id: instance_id, delete_volumes: true)

    ping_slack(
      'Quandl::Slack::InstanceDown',
      'Remove existing instance',
      'success',
      manifest.merge(
        completed: Time.now,
        hostname: instance.hostname,
        instance_id: instance.instance_id,
        private_ip: instance.private_ip,
        public_ip: instance.public_ip
      )
    )
  end
end
