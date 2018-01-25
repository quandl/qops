# frozen_string_literal: true

require 'thor'
require 'thor/group'
require 'aws-sdk'
require 'json'
require 'fileutils'
require 'active_support/all'
require 'pp'
require 'optparse'
require 'erb'
require 'rainbow'

require 'quandl/slack'

require_relative 'qops/environment'
require_relative 'qops/helpers'
require_relative 'qops/deployment/helpers'
require_relative 'qops/deployment/app'
require_relative 'qops/deployment/instances'
require_relative 'qops/deployment/stacks'
require_relative 'qops/cookbook/cookbook'

# Migrate this into quandl config project
module Quandl
  class Config < ::OpenStruct
    cattr_accessor :environment

    private

    def project_environment
      @_environment ||= @@environment || (defined?(Rails) ? ::Rails.env : nil) || ENV['RAILS_ENV'] || ENV['RAKE_ENV'] || ENV['QUANDL_ENV'] || 'default'
    end
  end
end
