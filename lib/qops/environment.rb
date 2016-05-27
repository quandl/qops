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

    def initialize
      %w(deploy_type region stack_id app_name).each do |v|
        fail "Please configure #{v} before continuing." unless option?(v)
      end

      begin
        opsworks.config.credentials.access_key_id
        opsworks.config.credentials.secret_access_key
      rescue => e
        raise "There may be a problem with your aws credentials. Please correct with `aws configure`. Error: #{e}"
      end
    end

    def application_id
      configuration.application_id unless configuration.application_id.blank?
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

    # Default 1 days
    def max_instance_duration
      configuration.max_instance_duration || 86_400
    end

    def clean_commands_to_ignore
      configuration.clean_commands_to_ignore.present? ? configuration.clean_commands_to_ignore : %w(update_custom_cookbooks update_agent configure shutdown)
    end

    def file_name
      self.class.file_name
    end

    def opsworks
      @_opsworks_client ||= Aws::OpsWorks::Client.new(region: configuration.region)
    end

    def ec2
      @_ec2_client ||= Aws::EC2::Client.new(region: configuration.region)
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
      !configuration.ebs_optimize.nil? ? configuration.ebs_optimize : !!(deploy_type =~ /production/) # rubocop:disable Style/DoubleNegation
    end

    private

    def method_missing(method_sym, *arguments, &block)
      if configuration.respond_to?(method_sym)
        configuration.send(method_sym, *arguments, &block)
      else
        super
      end
    end
  end
end
