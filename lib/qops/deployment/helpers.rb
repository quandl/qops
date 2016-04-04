module Qops::DeployHelpers
  extend ActiveSupport::Concern

  include Qops::Helpers

  included do
    class_option :branch, type: :string, aliases: '-b', desc: 'The branch to use when deploying to staging type environments'
  end

  private

  def config
    return @_config if @_config

    Qops::Environment.notifiers
    @_config ||= Qops::Environment.new

    fail "Invalid configure deploy_type detected: #{@_config.deploy_type}" unless %w(staging production).include?(@_config.deploy_type)

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

  def requested_hostname
    return @requested_hostname if @requested_hostname
    if config.deploy_type == 'staging'
      @requested_hostname = default_revision.parameterize
    elsif config.deploy_type == 'production'
      @requested_hostname = config.app_name
      existing_hostnames = retrieve_instances.map(&:hostname)
      @requested_hostname += "-#{existing_hostnames.sort.last.to_s.split('-').last.to_i + 1}"
    end

    @requested_hostname = @requested_hostname.gsub(/[^A-Za-z0-9\-]+/, '-').gsub(/-+/, '-')
    @requested_hostname = @requested_hostname[0..62]
    @requested_hostname = @requested_hostname.match(/^([A-Za-z0-9\-]+).*$/)[1]
  end

  def default_revision
    return 'master' unless config.deploy_type == 'staging'
    if options[:branch].present?
      options[:branch]
    elsif `git --version` # rubocop:disable Lint/LiteralInCondition
      `git symbolic-ref --short HEAD`.strip
    else
      'master'
    end
  end
end
