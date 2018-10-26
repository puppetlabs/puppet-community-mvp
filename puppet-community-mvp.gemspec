Gem::Specification.new do |s|
  s.name              = "puppet-community-mvp"
  s.version           = "0.0.3"
  s.date              = Date.today.to_s
  s.summary           = "Generate some stats about the Puppet Community."
  s.license           = 'Apache 2'
  s.email             = "ben.ford@puppet.com"
  s.authors           = ["Ben Ford"]
  s.has_rdoc          = false
  s.require_path      = "lib"
  s.executables       = %w( mvp )
  s.files             = %w( README.md LICENSE )
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("bin/**/*")
  s.add_dependency      "json"
  s.add_dependency      "histogram"
  s.add_dependency      "ascii_charts"
  s.add_dependency      "sparkr"
  s.add_dependency      "semantic_puppet"
  s.add_dependency      "httparty"
  s.add_dependency      "tty-spinner"
  s.add_dependency      "google-cloud"
  s.add_dependency      "puppet-itemize"

  s.description       = <<-desc
  Nothing exciting. Just gathers stats about the Puppet Community. Currently
  draws data from the Puppet Forge, GitHub, and Slack. Optionally pushes data
  into BigQuery for later consumption.

  Run `mvp --help` to get started.
  desc

end
