#! /usr/bin/env ruby
require 'json'

# This script attempts to identify any facts that create facts with dots in their names.

problems = []
Dir.glob('lib/facter/*').each do |fact|
  next unless File.file? fact
  if File.read(fact) =~ /Facter\.add.*\..* [do|{]/
    problems << [ "#{ENV['mvp_owner']}-#{ENV['mvp_name']}-#{ENV['mvp_version']}",
                  "https://forge.puppet.com/modules/#{ENV['mvp_owner']}/#{ENV['mvp_name']}",
                  File.basename(fact),
                  ENV['mvp_downloads']
                ]
  end
end

puts JSON.pretty_generate(problems)
