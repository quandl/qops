class Qops::Cookbook < Thor
  include Qops::Helpers

  desc 'vendor', 'Generate vendor directory to contain the cookbooks'
  def vendor
    initialize_run
    cleanup
    Dir.chdir(config.cookbook_dir) do
      system('berks vendor vendor -e opsworks')
    end
  end

  desc 'package', 'Package the cookbooks into a zip file in vendor'
  def package
    initialize_run
    Dir.chdir(config.cookbook_dir) do
      remove_zip_files
      system("zip -r #{artifact_name} vendor/*")
    end
  end

  desc 'upload', 'Uploads cookbooks to s3'
  def upload
    initialize_run
    s3.put_object(
      bucket: config.cookbook_s3_bucket,
      acl: 'private',
      key: remote_artifact_file,
      body: IO.read(local_artifact_file)
    )
  end

  desc 'update_custom_json', 'Upload custom json to stack'
  def update_custom_json
    initialize_run
    raw_json = File.read(File.join(config.cookbook_dir, config.cookbook_json))
    json = JSON.parse(raw_json)

    say(JSON.pretty_generate(json), :yellow)
    if yes?("Are you sure you want to update the custom JSON for opsworks stack #{config.stack_id}?", :yellow)
      config.opsworks.update_stack(
        stack_id: config.stack_id,
        custom_json: JSON.pretty_generate(json)
      )
      say('Updated!', :green)
    else
      say('You said no, so we\'re done here.', :yellow)
    end
  rescue JSON::ParserError
    say('Check your JSON for errors!', :red)
  end

  desc 'update_stack_cookbooks', 'Runs the opsworks command to update custom cookbooks.'
  def update_stack_cookbooks
    initialize_run
    if yes?("Are you sure you want to run the 'Update Custom Cookbooks' command on stack #{config.stack_id}?", :yellow)
      run_opsworks_command(
        stack_id: config.stack_id,
        command: {
          name: 'update_custom_cookbooks'
        }
      )
      say('Updated!', :green)
    else
      say('You said no, so we\'re done here.', :yellow)
      exit(-1)
    end
  end

  desc 'release', 'Zip, package and update a new cookbook as a release.'
  def release
    vendor && package && upload && update_custom_cookbooks && update_stack_cookbooks

    ping_slack('Quandl::Slack::Cookbook', 'Cookbook updated', 'success',
               command: 'opsworks cookbook release',
               status: 'success',
               name: config.cookbook_name,
               version: config.cookbook_version,
               stack: config.stack_id)

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
          url: "https://s3.amazonaws.com/#{config.cookbook_s3_bucket}/#{remote_artifact_file}"
        }
      )
      say('Cookbooks updated', :green)
    else
      say('You said no, so we\'re done here.', :yellow)
      exit(-1)
    end
  end

  desc 'cleanup', 'Cleanup all temporary files from the cookbook directory'
  def cleanup
    Dir.chdir(config.cookbook_dir) do
      remove_zip_files
      FileUtils.remove_dir('vendor') if File.directory?('vendor')
      say("Cleaned up directory '#{config.cookbook_dir}/vendor'", :green)
    end
  end

  private

  def initialize_run
    super
    config
  end

  def config
    return @_config if @_config

    @_config ||= Qops::Environment.new

    %w[cookbook_dir cookbook_s3_bucket cookbook_s3_path cookbook_name cookbook_version].each do |var|
      fail ArgumentError.new("Must specify a '#{var}' in the config") if !@_config.respond_to?(var) && !@_config.configuration.respond_to?(var)
    end

    fail ArgumentError.new("Cannot find/do not have access to cookbook directory: #{@_config.cookbook_dir}") unless Dir.exist?(@_config.cookbook_dir)

    @_config
  end

  def s3
    @s3 ||= Aws::S3::Client.new(**aws_configs)
  end

  def aws_configs
    aws_config = { region: 'us-east-1' }
    # use the profile if found
    options[:profile] ? aws_config[:profile] = options[:profile] : aws_config[:credentials] = config.opsworks.config.credentials.credentials
    aws_config
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
    say("Cleaned up directory '#{config.cookbook_dir}/*.zip'", :green)
  end
end
