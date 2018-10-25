require 'httparty'
require 'fileutils'
require 'puppet_x/binford2k/itemize'
require 'puppet_x/binford2k/itemize/runner'

class Mvp
  class Itemizer
    def initialize(options = {})
      @useragent = 'Puppet Community Stats Monitor'
      @forge     = options[:forge] ||'https://forge.puppet.com'
    end

    def run!(data, uploader)
      data.each do |mod|
        modname = mod['slug']
        version = mod['version']
        return if uploader.version_itemized?(modname, version)

        begin
          uploader.insert(:itemized, table(itemize(modname, version), mod))
        rescue => e
          $logger.error e.message
          $logger.debug e.backtrace.join("\n")
        end
      end
    end

    def download(path, modname, version)
      filename = "#{modname}-#{version}.tar.gz"
      Dir.chdir(path) do
        File.open(filename, "w") do |file|
          file << HTTParty.get( "#{@forge}/v3/files/#{filename}" )
        end
        system("tar -xf #{filename}")
        FileUtils.rm(filename)
      end
    end

    def itemize(modname, version)
      Dir.mktmpdir('mvp') do |path|
        download(path, modname, version)

        # not all modules have manifests
        manifests = "#{path}/#{modname}-#{version}/manifests"
        next {} unless File.directory?(manifests)

        options = {
          :manifests => [manifests],
          :external  => true,
        }
        runner = Puppet_X::Binford2k::Itemize::Runner.new(options).run!
        runner.results
      end
    end

    # Build a table with this schema
    # module | version | source | kind | element | count
    def table(itemized, data)
      modname      = data['slug']
      version      = data['version']
      dependencies = data['dependencies']

      itemized.map do |kind, elements|
        # the kind of element comes pluralized from puppet-itemize
        kind = kind.to_s.chomp('s')
        elements.map do |name, count|
          # TODO: this may suffer from collisions, (module foo, function foo, for example)
          depname = name.split('::').first
          source  = dependencies.find {|row| row.split('-').last == depname} rescue nil

          { :module => modname, :version => version, :source => source, :kind => kind, :element => name, :count => count }
        end
      end.flatten(1)
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
