class Qops::Cookbook < Thor
  class_option :environment, aliases: :e, default: 'staging'

  def initialize(*args)
    super
    config # Setup config in initial directory
  end

  desc 'vendor', 'Generate vendor directory to contain the cookbooks'
  def vendor
    cleanup
    Dir.chdir(config.cookbook_dir) do
      system('berks vendor vendor -e opsworks')
    end
  end

  desc 'package', 'Package the cookbooks into a zip file in vendor'
  def package
    Dir.chdir(config.cookbook_dir) do
      remove_zip_files
      system("zip -r #{artifact_name} vendor/*")
    end
  end

  desc 'upload', 'Uploads cookbooks to s3'
  def upload
    s3.put_object(
      bucket: config.cookbook_s3_bucket,
      acl: 'private',
      key: remote_artifact_file,
      body: IO.read(local_artifact_file)
    )
  end

  desc 'update_custom_json', 'Upload custom json to stack'
  def update_custom_json
    # load JSON and check for errors
    raw_json = File.read(File.join(config.cookbook_dir, 'custom.json'))
    json = JSON.parse(raw_json)
    say(json, :yellow)
    if yes?("Are you sure you want to update the custom JSON for opsworks stack #{config.stack_id}?", :yellow)
      config.opsworks.update_stack(
        stack_id: config.stack_id,
        custom_json: raw_json
      )
      say('Updated!', :green)
    else
      say('You said no, so we\'re done here.', :yellow)
    end
  rescue JSON::ParserError
    say('Check your JSON for errors!', :red)
  end

  desc 'release', 'Zip, package and update a new cookbook as a release.'
  def release
    vendor && package && upload && update_custom_cookbooks
    say('Released!', :green)
  end

  desc 'update_custom_cookbooks', 'Update the stack with the custom cookbooks!'
  def update_custom_cookbooks
    if yes?("Are you sure you want to update the custom the custom cookbook for opsworks stack #{config.stack_id}?", :yellow)
      config.opsworks.update_stack(
        stack_id: config.stack_id,
        use_custom_cookbooks: true,
        custom_cookbooks_source: {
          type: 's3',
          url: "https://s3.amazonaws.com/#{@_config.cookbook_s3_bucket}/#{remote_artifact_file}"
        })
      say('Cookbooks updated', :green)
    else
      say('You said no, so we\'re done here.', :yellow)
    end
  end

  desc 'cleanup', 'Cleanup all temporary files from the cookbook directory'
  def cleanup
    Dir.chdir(config.cookbook_dir) do
      remove_zip_files
      FileUtils.remove_dir('vendor') if File.directory?('vendor')
    end
  end

  private

  def config
    return @_config if @_config
    @_config ||= Qops::Environment.new

    %w(cookbook_dir cookbook_s3_bucket cookbook_s3_path cookbook_name cookbook_version).each do |var|
      fail ArgumentError.new("Must specify a '#{var}' in the config") unless @_config.send(var)
    end

    @_config
  end

  def s3
    @s3 ||= Aws::S3::Client.new(
      region: 'us-east-1',
      access_key_id: config.opsworks.config.credentials.access_key_id,
      secret_access_key: config.opsworks.config.credentials.secret_access_key
    )
  end

  def local_artifact_file
    File.join(config.cookbook_dir, artifact_name)
  end

  def remote_artifact_file
    File.join(config.cookbook_s3_path, artifact_name)
  end

  def artifact_name
    "#{config.cookbook_name}-#{config.cookbook_version}.zip"
  end

  def vendor_dir
    File.join(config.cookbook_dir, 'vendor')
  end

  def remove_zip_files
    FileUtils.rm Dir.glob("#{config.cookbook_name}*.zip")
  end
end
