require 'thor'
require 'aws-sdk'
require 'json'
require 'yaml'
require 'fileutils'
require 'byebug'

class Opsworks < Thor
  include Thor::Actions

  S3_BUCKET = 'quandl-cookbooks'.freeze

  option :environment, required: true
  option :cookbookdir, required: true
  desc 'testing', 'foo'
  def vendor
    Dir.chdir(cookbook_dir) do
      # must remove any zip files or else they will be included in vendor directory!
      remove_zip_files
      FileUtils.remove_dir('vendor') if File.directory?('vendor')
      system("berks vendor vendor -e opsworks")
    end
  end

  option :environment, required: true
  option :cookbookdir, required: true
  desc 'package', 'package the file'
  def package
    Dir.chdir(cookbook_dir) do
      remove_zip_files
      system("zip -r #{artifact_name} vendor/*")
    end
  end

  option :environment, required: true
  option :cookbookdir, required: true
  desc 'upload the file', 'upload it'
  def upload
    s3.put_object(
      bucket: S3_BUCKET,
      acl: 'private',
      key: remote_artifact_file,
      body: IO.read(local_artifact_file)
      )
  end

  option :environment, required: true
  option :cookbookdir, required: true
  desc 'update_custom_json', 'Do more stuff'
  def update_custom_json
    # load JSON and check for errors
    raw_json = File.read(File.join(cookbook_dir, 'custom.json'))
    json = JSON.parse(raw_json)
    say(json, :yellow)
    if yes?("Are you sure you want to update the custom JSON for #{stack_id}?", :yellow)
      opsworks.update_stack(
        stack_id: stack_id,
        custom_json: raw_json
        )
      say('Updated!', :green)
    else
      say('You said no, so we\'re done here.', :yellow)
    end
  rescue JSON::ParserError
    say('Check your JSON for errors!', :red)
  end

  option :environment, required: true
  option :cookbookdir, required: true
  desc 'release', 'foo'
  def release
    vendor && package && upload && update_custom_cookbooks
    say("Released!", :green)
  end

  option :environment, required: true
  option :cookbookdir, required: true
  desc 'update_custom_cookbooks', 'Update the stack!'
  def update_custom_cookbooks
    opsworks.update_stack(
      stack_id: stack_id,
      use_custom_cookbooks: true,
      custom_cookbooks_source: {
        type: 's3',
        url: "https://s3.amazonaws.com/#{S3_BUCKET}/#{remote_artifact_file}"
      })
    say('Cookbooks updated', :green)
  end

  private

  def stack_id
    raise ArgumentError.new('must specify a stack_id in config.yml') unless config['stack_id']
    config['stack_id']
  end

  def s3_path
    raise ArgumentError.new('must specify a s3_path in config.yml') unless config['s3_path']
    config['s3_path']
  end

  def cookbook_name
    raise ArgumentError.new('must specify a cookbook_name in config.yml') unless config['cookbook_name']
    config['cookbook_name']
  end

  def cookbook_dir
    raise ArgumentError.new('Not a valid directory') unless File.directory?(options[:cookbookdir])
    options[:cookbookdir]
  end

  def opsworks
    @opsworks ||= Aws::OpsWorks::Client.new(
      region: 'us-east-1',
      access_key_id: access_key_id,
      secret_access_key: secret_access_key
      )
  end

  def s3
    @s3 ||= Aws::S3::Client.new(
      region: 'us-east-1',
      access_key_id: access_key_id,
      secret_access_key: secret_access_key
      )
  end

  def config
    filename = File.join(cookbook_dir, 'config.yml')
    raise ArgumentError.new('config.yml does not exist') unless File.exist?(filename)
    Dir.chdir(cookbook_dir) do
      @config ||= YAML.load(ERB.new(File.read(filename)).result)
    end
    raise ArgumentError.new("Environment '#{options[:environment]}' does not exist in config.yml") unless @config.key?(options[:environment])
    @config[options[:environment]]
  end

  def access_key_id
    ENV.fetch('AWS_ACCESS_KEY')
  end

  def secret_access_key
    ENV.fetch('AWS_SECRET_ACCESS_KEY')
  end

  def local_artifact_file
    File.join(cookbook_dir, artifact_name)
  end

  def remote_artifact_file
    File.join(s3_path, artifact_name)
  end

  def artifact_name
    "#{cookbook_name}-#{version}.zip"
  end

  def vendor_dir
    File.join(cookbook_dir, 'vendor')
  end

  def remove_zip_files
    FileUtils.rm Dir.glob("#{cookbook_name}*.zip")
  end

  def version
    ver = config['version'].strip
    raise ArgumentError.new('must specify a version!') unless ver
    ver
  end
end
