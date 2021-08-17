#! /usr/bin/env ruby
require 'json'

# This script just counts how many manifests exist in a module and their maximum directory depth

manifests = Dir.glob('manifests/**/*.pp')
maxdepth  = manifests.map {|item| item.count('/') }.max
count     = manifests.count

puts JSON.pretty_generate(
  [[ "#{ENV['mvp_owner']}-#{ENV['mvp_name']}-#{ENV['mvp_version']}",
    "https://forge.puppet.com/modules/#{ENV['mvp_owner']}/#{ENV['mvp_name']}",
    ENV['mvp_downloads'],
    count,
    maxdepth,
  ]]
)
