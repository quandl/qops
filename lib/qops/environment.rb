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
      %w(deploy_type region stack_id).each do |v|
        fail "Please configure #{v} before continuing." unless v
      end

      begin
        opsworks.config.credentials.access_key_id
        opsworks.config.credentials.secret_access_key
      rescue => e
        raise "There may be a problem with your aws credentials with: aws configure: #{e}"
      end
    end

    def application_id
      configuration.application_id unless configuration.application_id.blank?
    end

    def command_log_lines
      configuration.command_log_lines || 100
    end

    def wait_iterations
      configuration.wait_iterations || 600
    end

    def autoscale_type
      configuration.autoscale_type || nil
    end

    def file_name
      self.class.file_name
    end

    def opsworks
      @_opsworks ||= Aws::OpsWorks::Client.new(region: configuration.region)
    end

    def cookbook_json
      configuration.cookbook_json || 'custom.json'
    end

    def option?(key)
      respond_to?(key.to_sym) || configuration.instance_variable_get(:@table).keys.include?(key.to_sym)
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
