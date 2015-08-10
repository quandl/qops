# Qops : Quandl Operations Helper

## Sample (with all options)

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
  cookbook_dir: cookbooks
  cookbook_name: wikiposit
  cookbook_version: "<%= IO.read(File.join(Dir.pwd, 'cookbooks/VERSION')).strip %>"
  cookbook_s3_bucket: quandl-cookbooks

staging:
  <<: *default
  deploy_type: :staging
  stack_id: 1bec9354-e1bc-4f31-8127-2208f2382dcb
  layer_id: 622555c4-fc06-4fc1-ba79-0a63fbd233f5
  application_id: 15904509-ace3-4d78-923e-ea10b3b2d433 # Optional. Deploy command will not run without application ID.
  subnet: subnet-0cde5d27
  cookbook_s3_path: staging/wikiposit
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

## Configuring Qops in your project

1. In your repo's config directory create a file called opsworks.yml. See sample.
2. Install gem `qops` to your system. Be sure to use gem install `qops`. Do not include it as part of the bundle of your repo as it is mean't to be run outside of the scope of your project.
3. Run `qops list` to get a list of commands you can run.
4. Run `qops help <command>` for more information on command argument options

## FAQ:

* The `qops` gem is currently not public. Please add your personal gemfury source to the gem path to install it.
