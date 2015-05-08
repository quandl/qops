require 'quandl/config'

class Qops::Environment
  include Quandl::Configurable

  attr_reader :revision

  def initialize
    puts "Reading 'config/#{file_name}.yml'"

    ['deploy-type', 'region', 'stack_id'].each do |v|
      fail "Please configure #{v} before continuing." unless v
    end

    begin
      opsworks.config.credentials.access_key_id
      opsworks.config.credentials.secret_access_key
    rescue => e
      raise 'Please update your aws credentials with: aws configure'
    end

    puts "Running commands in deploy environment: #{deploy_type}"

    @revision = (deploy_type == :staging ? `git symbolic-ref --short HEAD`.strip : 'master')
  end

  def file_name
    'opsworks'
  end

  def opsworks
    @_opsworks ||= Aws::OpsWorks::Client.new(region: configuration.region)
  end

  def method_missing(method_sym, *arguments, &block)
    if configuration.respond_to?(method_sym)
      configuration.send(method_sym, *arguments, &block)
    else
      super
    end
  end
end