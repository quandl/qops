class Qops::Deploy < Thor
  include Qops::DeployHelpers

  desc 'app', 'Deploy the latest version of the app to the environment'
  def app
    if config.deploy_type == :staging
      instances = [retrieve_instance].compact
      if instances.count == 0
        puts 'Could not find instance to deploy to. Perhaps you need to run "rake deploy:instance:up" first'
        exit(-1)
      end

      puts "Preparing to deploy branch #{config.revision} to #{instances.first.hostname}"
    else
      instances = retrieve_instances
      puts "Preparing to deploy branch #{config.revision} to all servers (#{instances.map(&:hostname).join(', ')})"
    end

    base_deployment_params = {
      stack_id: config.stack_id,
      app_id: config.application_id,
      command: { name: 'deploy' },
      custom_json: custom_json.to_json
    }

    manifest = { environment: config.deploy_type }

    # Deploy the first instance with migration on
    print "Migrating and deploying first instance (#{instances.first.hostname}) ..."
    deployment_params = base_deployment_params
    deployment_params[:command].merge!(args: { migrate: ['true'] })
    run_opsworks_command(deployment_params, [instances.first.instance_id])
    ping_slack(
      'Quandl::Slack::Release',
      "Deployed and migrated instance '#{instances.first.hostname}'",
      'success',
      manifest.merge(
        app_name: config.app_name,
        command: 'deploy + migrate',
        migrate: true,
        completed: Time.now,
        hostname: instances.first.hostname,
        instance_id: instances.first.instance_id
      )
    )

    # Deploy any remaining instances with migration off for production
    return unless config.deploy_type == :production && instances.count > 1

    print 'Deploying remaining instances ...'
    deployment_params = base_deployment_params
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
