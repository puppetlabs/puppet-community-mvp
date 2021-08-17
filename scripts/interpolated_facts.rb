#! /usr/bin/env ruby
require 'json'

# This complicated looking regex will count the number of facts that are named via interpolated strings.
# in other words, Facter.add("interface#{count}") or the like.

problems = []
Dir.glob('lib/facter/*').each do |fact|
  next unless File.file? fact
  if File.read(fact) =~ /Facter\.add\("\w*#\{.*\}\w*"\)/
    problems << [ "#{ENV['mvp_owner']}-#{ENV['mvp_name']}-#{ENV['mvp_version']}",
                  "https://forge.puppet.com/modules/#{ENV['mvp_owner']}/#{ENV['mvp_name']}",
                  File.basename(fact),
                  ENV['mvp_downloads']
                ]
  end
end

puts JSON.pretty_generate(problems)
