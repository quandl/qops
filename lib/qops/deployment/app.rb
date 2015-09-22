class Qops::Deploy < Thor
  include Qops::DeployHelpers

  desc 'app', 'Deploy the latest version of the app'
  def app
    initialize_run

    if config.deploy_type == :staging
      instances = [retrieve_instance].compact
      if instances.count == 0
        raise 'Could not find instance to deploy to. Perhaps you need to run "qops:instance:up" first'
      end

      puts "Preparing to deploy branch #{default_revision} to instance #{instances.first.hostname}"
    else
      instances = retrieve_instances
      puts "Preparing to deploy default branch to all servers (#{instances.map(&:hostname).join(', ')})"
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

    if config.deploy_type != :production
      base_deployment_params[:custom_json] = custom_json.to_json
    end

    manifest = { environment: config.deploy_type }

    # Deploy the first instance with migration on
    print "Migrating and deploying first instance (#{instances.first.hostname}) ..."
    deployment_params = base_deployment_params.deep_dup
    should_migrate = !config.option?(:migrate) || config.option?(:migrate) && config.migrate == true
    deployment_params[:command].merge!(args: { migrate: ['true'] }) if should_migrate
    run_opsworks_command(deployment_params, [instances.first.instance_id])
    ping_slack(
      'Quandl::Slack::Release',
      "Deployed and migrated instance '#{instances.first.hostname}'",
      'success',
      manifest.merge(
        app_name: config.app_name,
        command: 'deploy + migrate',
        migrate: "#{should_migrate}",
        completed: Time.now,
        hostname: instances.first.hostname,
        instance_id: instances.first.instance_id
      )
    )

    # Deploy any remaining instances with migration off for production
    return unless config.deploy_type == :production && instances.count > 1

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
        hostname: instances.map(&:hostname),
        instance_id: instances.map(&:instance_id)
      )
    )
  end
end
