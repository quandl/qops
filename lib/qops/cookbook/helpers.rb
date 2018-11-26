# frozen_string_literal: true

module Qops::CookbookHelpers
  include Qops::Helpers

  def self.included(mod)
    super
    return unless mod.respond_to?(:class_option)

    mod.class_option :environment, aliases: '-e', desc: 'The environment to use when running commands.'
    mod.class_option :profile, type: :string, aliases: '-p', desc: 'An AWS profile to use'
    mod.class_option :force_config, type: :boolean, aliases: '-f', desc: 'Force qops to read options from config. by default qops will search aws opsworks stack'
    mod.class_option :verbose, type: :boolean, aliases: '-v', desc: 'Provides additional information when running for debugging purposes.'
  end

  private

  def config
    return @_config if @_config

    @_config ||= Qops::Environment.new(profile: options[:profile], force_config: options[:force_config], verbose: options[:verbose])

    %w[cookbook_dir cookbook_s3_bucket cookbook_s3_path cookbook_name cookbook_version].each do |var|
      fail ArgumentError.new("Must specify a '#{var}' in the config") if !@_config.respond_to?(var) && !@_config.configuration.respond_to?(var)
    end

    fail ArgumentError.new("Cannot find/do not have access to cookbook directory: #{@_config.cookbook_dir}") unless Dir.exist?(@_config.cookbook_dir)

    @_config
  end

end
