require 'thor'
require 'aws-sdk'
require 'json'
require 'fileutils'
require 'active_support/all'

require 'quandl/slack'

# The following should get merged into quandl-config project.
require 'erb'
module Quandl
  class Config
    private

    def project_environment
      defined?(Rails) ? ::Rails.env : (ENV['RAILS_ENV'] || ENV['RAKE_ENV'] || ENV['QUANDL_ENV'] || 'staging')
    end
  end
end

module Qops
end

require_relative 'qops/deployment/helpers'
require_relative 'qops/deployment/app'
require_relative 'qops/deployment/instances'
require_relative 'qops/cookbook/cookbook'
require_relative 'qops/environment'
