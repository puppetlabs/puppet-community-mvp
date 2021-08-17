#! /usr/bin/env ruby
require 'json'

# This script identifies any facts this module has that invoke facter to gather values of other facts.
# This is identified by the "--no-external-facts" argument, since without it Facter will forkbomb

problems = []
Dir.glob('facts.d/*').each do |fact|
  next unless File.file? fact
  if File.read(fact) =~ /--no-external-facts/
    problems << [ "#{ENV['mvp_owner']}-#{ENV['mvp_name']}-#{ENV['mvp_version']}",
                  "https://forge.puppet.com/modules/#{ENV['mvp_owner']}/#{ENV['mvp_name']}",
                  File.basename(fact),
                  ENV['mvp_downloads']
                ]
  end
end

puts JSON.pretty_generate(problems)
