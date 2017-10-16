class Qops::Stack < Thor
  include Qops::DeployHelpers

  desc 'describe', 'show basic stack info'
  method_option :name, type: :string, aliases: '-n', desc: 'describe the stack with matching name'
  def describe
    initialize_run
    puts JSON.pretty_generate(show_stack(name: options[:name]))
  end


end