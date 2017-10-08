module Qops::DeployHelpers
  extend ActiveSupport::Concern

  include Qops::Helpers

  included do
    class_option :custom_json, type: :string, aliases: '-j', desc: 'A custom json that will be used during a deployment of the app. ex: \'{ "custom_attrs": "are awesome!"}\''
    class_option :branch, type: :string, aliases: '-b', desc: 'The branch to use when deploying to staging type environments'
    class_option :hostname, type: :string, aliases: '-h', desc: 'Fully override the hostname that qops would normally give the instance'
    class_option :profile, type: :string, aliases: '-p', desc: 'An AWS profile to use'
  end

  private

  def config
    return @_config if @_config
    Qops::Environment.notifiers
    @_config ||= Qops::Environment.new(profile: options[:profile])

    fail "Invalid configure deploy_type detected: #{@_config.deploy_type}" unless %w[staging production].include?(@_config.deploy_type)

    @_config
  end

  def retrieve_instances(options = {})
    # Describe and create instances as necessary
    instances_results = config.opsworks.describe_instances({ layer_id: config.layer_id }.merge(options))

    # Determine if instance exists.
    instances_results.data.instances
  end

  def retrieve_instance(instance_id = nil)
    # Retrieve a specific instance as necessary
    if instance_id
      instances_results = config.opsworks.describe_instances(instance_ids: [instance_id])
      return instances_results.data.instances.first
    end

    # Get instance based on hostname
    instances_results = config.opsworks.describe_instances(layer_id: config.layer_id)

    # Determine if instance exists.
    instances = instances_results.data.instances

    return unless instances.map(&:hostname).include?(requested_hostname)

    instances.find { |k| k.hostname == requested_hostname }
  end

  def tag_instance(instance)
    print "Tagging instance #{instance.hostname}\n"

    tags = [
      {
        key: 'environment',
        value: config.deploy_type
      },
      {
        key: 'branch',
        value: revision_used
      },
      {
        key: 'app',
        value: config.app_name
      }
    ]

    if config.deploy_type == 'staging'
      tags << {
        key: 'cleanable',
        value: 'true'
      }
    end

    config.ec2.create_tags(
      resources: [instance.ec2_instance_id],
      tags: tags
    )
  end

  def requested_hostname
    return @requested_hostname if @requested_hostname
    if options[:hostname]
      @requested_hostname = options[:hostname]
      puts "NOTE: You have specified a custom hostname of #{@requested_hostname}. Be sure to continue to use this hostname for future commands to avoid problems."

    # Alternative flow if user has not overridden the hostname
    else
      if config.deploy_type == 'staging'
        @requested_hostname = revision_used.parameterize
      elsif config.deploy_type == 'production'
        @requested_hostname = config.app_name
        existing_hostnames = retrieve_instances.map(&:hostname)
        @requested_hostname += "-#{existing_hostnames.sort.last.to_s.split('-').last.to_i + 1}"
      end
      @requested_hostname = config.hostname_prefix + @requested_hostname
    end

    @requested_hostname = @requested_hostname.gsub(/[^A-Za-z0-9\-]+/, '-').gsub(/-+/, '-')
    @requested_hostname = @requested_hostname[0..62]
    @requested_hostname = @requested_hostname.match(/^([A-Za-z0-9\-]+).*$/)[1]
    @requested_hostname
  end

  def revision_used
    return 'master' unless config.deploy_type == 'staging'
    if options[:branch].present?
      options[:branch]
    elsif `git --version` # rubocop:disable Lint/LiteralInCondition
      `git symbolic-ref --short HEAD`.strip
    else
      'master'
    end
  end

  def show_stack(options = {})
    stack = config.find_stack(options)
    {
      name: stack.name,
      stack_id: stack.stack_id,
      subnet: stack.default_subnet_id,
      layers: config.layers(options).map { |layer| layer.to_h.slice(:name, :layer_id, :shortname) },
      apps: config.apps(options).map { |app| app.to_h.slice(:name, :app_id) },
      config_manager: stack.configuration_manager.to_h
    }
  end
end
