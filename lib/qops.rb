require 'thor'
require 'aws-sdk'
require 'json'
require 'fileutils'
require 'active_support/all'

require 'quandl/slack'

module Qops
end

require_relative 'qops/environment'
require_relative 'qops/helpers'
require_relative 'qops/deployment/helpers'
require_relative 'qops/deployment/app'
require_relative 'qops/deployment/instances'
require_relative 'qops/cookbook/cookbook'

# The following should get refactored and merged into quandl-config project.
if ARGV[0] && ARGV[0].start_with?('qops')
  project_root = Pathname.new(Quandl::ProjectRoot.root)
  file_path = project_root.join('config', "#{Qops::Environment.file_name}.yml")

  if File.exist?(file_path)
    raw_config = File.read(file_path)
    erb_config = ERB.new(raw_config).result
    configs = YAML.load(erb_config)
    ENV['QUANDL_ENV'] ||= Thor::Shell::Color.new.ask("\nRun command using config:", :yellow, limited_to: configs.keys.reject { |g| g.start_with?('_') }, echo: false)
    puts "\nRunning commands with config #{ENV['QUANDL_ENV']}"
  end
end

require 'erb'
module Quandl
  class Config
    private

    def project_environment
      ENV['QUANDL_ENV']
    end
  end
end
