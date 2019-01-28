# Qops : Quandl Operations Helper

## Configuring Qops in your project

1.  In your repo's config directory create a file called opsworks.yml. See sample.
2.  Install gem `qops` to your system. Be sure to use gem install `qops`. Do not include it as part of the bundle of your repo as it is mean't to be run outside of the scope of your project.
3.  Run `qops list` to get a list of commands you can run.
4.  Run `qops help <command>` for more information on command argument options

## FAQ:

### Q: Can I Override Built-In Templates

You can create a overridden_built_in_templates folder within you cookbooks folder.
/cookbooks/overridden_built_in_templates/unicorn/templates/default/unicorn.conf.erb

### Q: The `qops` gem is currently not public. How do I access it?

Please add your personal gemfury source to the gem path to install it.

### Q: For the `qops qops:instance:run_command` command, it provides two options: one is run commands against all instances of the stack all in once, one is run commands on each instances of the stack one by one randomly. How do I use this?

When running commands one by one, between each execution of the command, there will be a delay. The delay is config by wait_deploy. By default it is 180 seconds when it is not defined. For now, run_command command will only support commends `setup` `configure` `install_dependencies` `update_dependencies`, `execute_recipes`, since commands `update_custom_cookbooks` `deploy` was implemented before.

When run command `execute_recipes`, a comma separated recipes should be supply, for example: cookbookname::recipename_one,cookbookname::recipename_two 

### Q: How do I use QOPS to override env variables on my opsworks CHEF 11 stack?

You can use the custom json flag for this. Example:

```qops qops:instance:up -e staging -j '{ "deploy" : { "wikiposit" : { "environment_variables" : { "ENV_VARIABLE_TO_OVERIDE": "X" } } } }'```

In this case the `wikiposit` is the opsworks app wikiposit. You will need to change this to whichever app you are deploying.

See also: <http://docs.aws.amazon.com/opsworks/latest/userguide/apps-environment-vars.html>

## Sample Config (with all options)

```
_daily_schedule: &daily_schedule
  '13': 'on'
  '14': 'on'
  '15': 'on'
  '16': 'on'
  '17': 'on'
  '18': 'on'
  '19': 'on'
  '20': 'on'
  '21': 'on'
  '22': 'on'

_weekly_schedule: &weekly_schedule
  monday: *daily_schedule
  tuesday: *daily_schedule
  wednesday: *daily_schedule
  thursday: *daily_schedule
  friday: *daily_schedule

_default: &default
  wait_iterations: 600 # Optional
  command_log_lines: 100 # Optional
  autoscale_type: ~ # Optional
  region: us-east-1
  app_name: 'wikiposit'
  instance_type: 't2.small'
  max_instance_duration: 86400 # Optional
  clean_commands_to_ignore: ['configure', 'shutdown] # Optional: A list of opsworks commands to ignore when calculating that last run time for the clean command. Ignores `configure` and `shutdown` commands by default.  
  cookbook_dir: cookbooks
  cookbook_name: wikiposit
  cookbook_version: "<%= IO.read(File.join(Dir.pwd, 'cookbooks/VERSION')).strip %>"
  cookbook_s3_bucket: quandl-cookbooks

staging:
  <<: *default
  deploy_type: :staging
  stack_id: 1aec9354-e1bc-4f31-8627-2208f2382dcb
  layer_id: 622555c4-fc07-4ff1-ba79-0a63fbd233f5
  application_id: 15904509-ace3-4d78-923e-ea10b3b2d433 # Optional. Deploy command will not run without application ID.
  subnet: subnet-0cde5d27
  cookbook_s3_path: staging/my-app
```

## Sample Slack.yml

If you create a `config/quandl/slack.yml` file as so slack messages can be enabled for deployments under various environments.

```
defaults: &defaults
  webhook_url: https://hooks.slack.com/services/......
  notifiers: &default_notifiers
    cookbook:
      channel: '#releases'
      username: My App Cookbooks
      icon_emoji: ':book:'
    release:
      channel: '#releases'
      username: My App
      icon_emoji: ':rocket:'
    instance_up:
      channel: '#releases'
      username: My App
      icon_emoji: ':chart_with_upwards_trend:'
    instance_down:
      channel: '#releases'
      username: My App
      icon_emoji: ':chart_with_downwards_trend:'

development:
  <<: *defaults
```
