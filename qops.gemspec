# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'qops/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'qops'
  s.version     = Qops::VERSION
  s.authors     = ['Matthew Basset', 'Clement Leung', 'Jason Byck', 'Jun Li', 'Michael Fich']
  s.email       = ['support@quandl.com']
  s.homepage    = 'https://github.com/quandl/opsworks_commands'
  s.summary     = 'Helper commands for deployment of opsworks projects.'
  s.description = 'Help to automate opsworks project deployments with single commands.'

  s.license     = 'MIT'

  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 2.1'

  s.files = Dir['{lib,bin}/**/*', 'README.md']
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.require_paths = ['lib']

  s.add_runtime_dependency 'activesupport', '>= 4.2.1', '< 7.0'
  s.add_runtime_dependency 'aws-sdk', '~> 3.0'
  s.add_runtime_dependency 'quandl-config', '~> 1.0.0'
  s.add_runtime_dependency 'quandl-slack', '~> 0.0.2'
  s.add_runtime_dependency 'rainbow', '~> 2.0.0'
  s.add_runtime_dependency 'thor', '~> 0.20.0'
end
