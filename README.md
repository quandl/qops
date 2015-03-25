# opsworks_commands

1. In your repo's cookbook, create a file called config.yml (see https://github.com/quandl/jeffbox/blob/master/cookbook/config.yml for example)
2. To upload custom cookbook to s3 and add it to your opsworks stack, run the command `thor opsworks:release --cookbookdir=<full path to config.yml>`
3. To upload custom json attributes to opsworks, run the command `thor opsworks:update_custom_json --cookbookdir=<full path to config.yml>`
