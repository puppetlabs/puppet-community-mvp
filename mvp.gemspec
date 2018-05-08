Gem::Specification.new do |s|
  s.name              = "mvp"
  s.version           = "0.0.1"
  s.date              = Date.today.to_s
  s.summary           = "Generate some stats about the Puppet Community."
  s.license           = 'Apache 2'
  s.email             = "ben.ford@puppet.com"
  s.authors           = ["Ben Ford"]
  s.has_rdoc          = false
  s.require_path      = "lib"
  s.executables       = %w( mvp )
  s.files             = %w( README.md Rakefile LICENSE )
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("bin/**/*")
  s.add_dependency      "json"
  s.add_dependency      "histogram"
  s.add_dependency      "ascii_charts"
  s.add_dependency      "histogram"
  s.add_dependency      "sparkr"
  s.add_dependency      "semantic_puppet"

  s.description       = <<-desc
  Nothing exciting. Just some stats about the Puppet Forge.

  Run `mvp --help` to get started.
  desc

end
