require 'quandl/config'

module Qops
  class Environment
    include Quandl::Configurable

    def self.file_name
      'opsworks'
    end

    def self.notifiers
      return @_notifiers unless @_notifiers.nil?
      if File.exist?('config/quandl/slack.yml')
        @_notifiers ||= Quandl::Slack.autogenerate_notifiers
      else
        @_notifiers = false
        print_with_colour('Slack notifications disabled. Could not find slack configuration at: config/quandl/slack.yml', :warning)
      end
    rescue NoMethodError => e
      print_with_colour("Slack notifications disabled due to an error. #{e}", :warning)
    end

    def self.print_with_colour(message, level = :normal)
      case level
      when :error
        puts Rainbow(message).bg(:black).red
      when :warning
        puts Rainbow(message).bg(:black).yellow
      else
        puts message
      end
    end

    def initialize(profile: nil, force_config: false)
      @_aws_config = { region: configuration.region }
      @_aws_config[:profile] = profile unless profile.nil?
      @_force_config = force_config
      puts Rainbow("using aws profile #{profile}").bg(:black).green unless profile.nil?

      %w[deploy_type region app_name].each do |v|
        fail "Please configure #{v} before continuing." unless option?(v)
      end

      fail 'Please configure the layer_name if you are allowing qops to search aws stacks' unless option?('layer_name')

      # if being forced to use config , then stack_id is a requirement
      fail 'Please configure stack_id or stack_name before continuing' unless option?('stack_id') || option?('stack_name')

      begin
        opsworks.config.credentials.credentials unless profile
      rescue => e # rubocop:disable Lint/RescueWithoutErrorClass
        raise "There may be a problem with your aws credentials. Please correct with `aws configure`. Error: #{e}"
      end
    end

    def stack(options = {})
      return @_stack if @_stack
      # find out if the config is using stack id or name
      key = search_key(options)
      value = options[key] || configuration.send(key)
      # aws uses the term 'name' to reference a stack name
      key = :name if key == :stack_name
      @_stack = search_stack(key, value)
    end

    def stack_id(options = {})
      return configuration.stack_id if @_force_config
      stack(options).stack_id
    end

    def subnet(options = {})
      return configuration.subnet if @_force_config
      stack(options).default_subnet_id
    end

    def layers(_options = {})
      opsworks.describe_layers(stack_id: stack_id).layers
    end

    def layer_id(options = {})
      return configuration.layer_id if @_force_config
      name = options[:layer_name] || configuration.layer_name
      layers.find { |layer| layer.name.casecmp(name) }.layer_id
    end

    def chef_version(options = {})
      stack(options).configuration_manager.version.to_f
    end

    def apps(_options = {})
      opsworks.describe_apps(stack_id: stack_id).apps
    end

    def application_id(options = {})
      return configuration.application_id if @_force_config
      apps(options).first.app_id
    end

    def deploy_type
      configuration.deploy_type.to_s
    end

    def command_log_lines
      configuration.command_log_lines || 100
    end

    def wait_iterations
      configuration.wait_iterations || 600
    end

    def wait_deploy
      configuration.wait_deploy || 180
    end

    def autoscale_type
      configuration.autoscale_type || nil
    end

    def opsworks_os(options = {})
      return configuration.os if @_force_config
      find_stack(options).default_os
    end

    # Default 1 days
    def max_instance_duration
      configuration.max_instance_duration || 86_400
    end

    def clean_commands_to_ignore
      configuration.clean_commands_to_ignore.present? ? configuration.clean_commands_to_ignore : %w[update_custom_cookbooks update_agent configure shutdown]
    end

    def file_name
      self.class.file_name
    end

    def opsworks
      @_opsworks_client ||= Aws::OpsWorks::Client.new(**@_aws_config)
    end

    def ec2
      @_ec2_client ||= Aws::EC2::Client.new(**@_aws_config)
    end

    def elb
      @_elb_client ||= Aws::ElasticLoadBalancing::Client.new(region: 'us-east-1', profile: @_aws_config[:profile])
    end

    def cookbook_json
      configuration.cookbook_json || 'custom.json'
    end

    def option?(key)
      respond_to?(key.to_sym) || configuration.instance_variable_get(:@table).keys.include?(key.to_sym)
    end

    def root_volume_size
      configuration.root_volume_size || 30
    end

    def hostname_prefix
      configuration.hostname_prefix || ''
    end

    def ebs_optimize
      !configuration.ebs_optimize.nil? ? configuration.ebs_optimize : !deploy_type !~ /production/
    end

    private

    def identity_from_config
      configuration.stack_id ? :stack_id : :stack_name
    end

    def search_key(options = {})
      key = if !options[:name].nil?
              :name
            elsif !options[:stack_id].nil?
              :stack_id
            else
              id = identity_from_config
              msg = Rainbow("Using opsworks.yml config #{id}: #{configuration.send(id)}")
              puts(msg.bg(:black).green)
              id
            end
      key
    end

    def search_stack(key, value)
      stack = opsworks.describe_stacks.stacks.find { |s| s.send(key) == value }
      unless stack
        puts Rainbow("Could not find stack with #{key} = #{value}").bg(:black).red
        exit(-1)
      end
      stack
    end

    def method_missing(method_sym, *arguments, &block) # rubocop:disable Style/MethodMissing
      if configuration.respond_to?(method_sym)
        configuration.send(method_sym, *arguments, &block)
      else
        super
      end
    end
  end
end
