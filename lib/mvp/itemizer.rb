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

        $logger.debug "Itemizing #{modname}-#{version}"
        begin
          rows = table(itemize(modname, version), mod)
          uploader.insert(:itemized, rows) unless rows.empty?
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
      modname      = data['name']
      slug         = data['slug']
      version      = data['version']
      dependencies = data['dependencies']

      itemized.map do |kind, elements|
        # the kind of element comes pluralized from puppet-itemize
        kind = kind.to_s
        kind = kind.end_with?('ses') ? kind.chomp('es') : kind.chomp('s')
        elements.map do |name, count|
          if name == modname
            depname = name
          else
            # This relies on a little guesswork.
            segments = name.split('::')                       # First see if its already namespaced and we can just use it
            segments = name.split('_') if segments.size == 1  # If not, then maybe it follows the pattern like 'mysql_password'
            depname  = segments.first
          end

          # There's a chance of collisions here. For example, if you depended on a module
          # named 'foobar-notify' and you used a 'notify' resource, then the resource would
          # be improperly linked to that module. That's a pretty small edge case though.
          source  = dependencies.find {|row| row.split('-').last == depname} rescue nil

          { :module => slug, :version => version, :source => source, :kind => kind, :element => name, :count => count }
        end
      end.flatten(1)
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
