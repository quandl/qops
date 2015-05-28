class Qops::Instance < Thor
  include Qops::DeployHelpers

  desc 'up', 'Deploy the current branch to a new or existing environment (default: staging)'
  def up
    # Get the instance(s) to work with if they exist. In production we always create a new instacne
    instance = retrieve_instance if config.deploy_type == :staging

    # Create the instance if necessary
    if instance
      instance_id = instance.instance_id
      puts "Existing instance #{requested_hostname}"
    else
      params = {
        stack_id: config.stack_id,
        layer_ids: [config.layer_id],
        instance_type: config.instance_type,
        os: 'Ubuntu 14.04 LTS',
        hostname: requested_hostname,
        subnet_id: config.subnet,
        auto_scaling_type: config.autoscale_type
      }
      puts 'Creating instance with params: ' + params.inspect
      instance_id = config.opsworks.create_instance(params).data.instance_id
      creating_instance = true
    end

    instance_results = config.opsworks.describe_instances(instance_ids: [instance_id])
    instance = instance_results.data.instances.first

    # Set up the automatic boot scheduler
    if config.deploy_type == :staging && config.autoscale_type == 'timer'
      print 'Setting up weekly schedule ...'
      config.opsworks.set_time_based_auto_scaling(instance_id: instance_id, auto_scaling_schedule: config.schedule)
      print "done\n"
    end

    # Record the initial instance before doing anything.
    initial_instance_state = instance

    # Start the instance if necessary
    print 'Booting instance ...'
    unless %w(online booting).include?(instance.status)
      config.opsworks.start_instance(instance_id: instance_id)
    end

    manifest = {
      environment: config.deploy_type,
      app_name: config.app_name,
      command: 'add instance'
    }

    # Boot the instance
    iterator(manifest) do |i|
      instance_results = config.opsworks.describe_instances(instance_ids: [instance_id])
      instance = instance_results.data.instances.first

      if %w(booting requested pending).include?(instance.status)
        print '.'
        print " #{instance.status} :" if been_a_minute?(i)
      else
        puts ' ' + instance.status
        true
      end
    end

    puts "Public IP: #{instance.public_ip}"
    puts "Private IP: #{instance.private_ip}"

    setup_instance(instance, initial_instance_state, manifest)

    if creating_instance
      ping_slack('Quandl::Slack::InstanceUp', 'Created another instance', 'success',
                 manifest.merge(
                   completed: Time.now,
                   hostname: instance.hostname,
                   instance_id: instance.instance_id,
                   private_ip: instance.private_ip,
                   public_ip: instance.public_ip.blank? ? 'N/A' : instance.public_ip
                 )
                )
    end

    # Deploy the latest code to instance
    Qops::Deploy.new.app
  end

  desc 'down', 'Remove the instance associated with this branch or one given (default: staging, current branch)'
  def down
    # Get the instance to shutdown
    if config.deploy_type == :staging
      instance = retrieve_instance
    elsif config.deploy_type == :production
      instance = retrieve_instances.first
    end

    if instance.nil?
      puts 'No instance available to shutdown'
      exit(0)
    else
      instance_id = instance.instance_id
    end

    # Remove schedule if time based instance
    if config.autoscale_type == 'timer'
      config.opsworks.set_time_based_auto_scaling(instance_id: instance_id, auto_scaling_schedule: {})
    end

    # Attempt to shutdown the instance
    unless instance.status == 'stopped'
      print "Attempting instance #{instance_id}-#{instance.hostname} shutdown ..."
      config.opsworks.stop_instance(instance_id: instance_id)
    end

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
    config.opsworks.delete_instance(instance_id: instance_id)

    ping_slack('Quandl::Slack::InstanceDown', 'Remove existing instance', 'success',
               manifest.merge(
                 completed: Time.now,
                 hostname: instance.hostname,
                 instance_id: instance.instance_id,
                 private_ip: instance.private_ip,
                 public_ip: instance.public_ip
               )
              )

    puts 'Success'
  end

  private

  def setup_instance(instance, initial_instance_state, manifest)
    # If the previous instance setup failed then run the setup task again when trying to bring up the instance.
    if initial_instance_state.status == 'setup_failed'
      print 'Setup instance ...'
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
      print 'Setup instance ...'
      iterator(manifest) do |i|
        instance_results = config.opsworks.describe_instances(instance_ids: [instance.instance_id])
        instance = instance_results.data.instances.first

        if %w(online).include?(instance.status)
          puts ' ' + instance.status
          true
        elsif %w(setup_failed).include?(instance.status)
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
end
