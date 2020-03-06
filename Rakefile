require 'fileutils'

imagename='gcr.io/puppetlabs.com/api-project-531226060619/mvp'

task :default do
  system("rake -T")
  require 'pry'
  binding.pry

end

def version
  version = `git describe --tags  --abbrev=0`.chomp.sub('v','')
  version.empty? ? '0.0.0' : version
end

def next_version(type = :patch)
  section = [:major,:minor,:patch].index type

  n = version.split '.'
  n[section] = n[section].to_i + 1
  n.join '.'
end


desc "Build Docker image"
task 'docker:build' do
  Dir.chdir('build') do
    system("docker build --no-cache=true -t #{imagename}:#{version} -t #{imagename}:latest .")
    puts "Start container manually with: docker run -v \"$(pwd)/data\":/var/run/mvp -it #{imagename}"
    puts 'Or rake docker::run'
  end
end

desc "Build Docker image"
task 'docker:run' do
  `docker run -v "$(pwd)/data":/var/run/mvp -it #{imagename}`
end

desc "Upload image to Docker Hub"
task 'docker:push' => ['docker:build'] do
  system("docker push #{imagename}:#{version}")
  system("docker push #{imagename}:latest")
end
