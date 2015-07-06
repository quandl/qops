module Qops::DeployHelpers
  include Qops::Helpers

  private

  def initialize_options
    config.revision = options[:branch] if options[:branch]
  end

  def config
    return @_config if @_config

    Qops::Environment.notifiers
    @_config ||= Qops::Environment.new

    fail "Invalid configure deploy_type detected: #{@_config.deploy_type}" unless [:staging, :production].include?(@_config.deploy_type)

    @_config
  end

  def custom_json
    return @_custom_json if @_custom_json

    application_name = config.opsworks.describe_apps(app_ids: [config.application_id]).apps.first.name

    @_custom_json = {
      deploy: {
        application_name => {
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

  def requested_hostname
    return @requested_hostname if @requested_hostname
    if config.deploy_type == :staging
      @requested_hostname = "#{config.app_name}-#{config.deploy_type}-#{config.revision.parameterize}"
    elsif config.deploy_type == :production
      @requested_hostname = "#{config.app_name}"
      existing_hostnames = retrieve_instances.map(&:hostname)
      @requested_hostname += "-#{existing_hostnames.last.to_s.split('-').last.to_i + 1}"
    end

    @requested_hostname = @requested_hostname[0..62]
  end
end
