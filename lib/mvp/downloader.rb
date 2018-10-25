require 'json'
require 'httparty'
require 'tty-spinner'
require 'semantic_puppet'
require 'mvp/monkeypatches'
require 'mvp/itemizer'

class Mvp
  class Downloader
    def initialize(options = {})
      @useragent = 'Puppet Community Stats Monitor'
      @cachedir  = options[:cachedir]
      @forgeapi  = options[:forgeapi] ||'https://forgeapi.puppet.com'
      @itemizer  = Mvp::Itemizer.new(options)
    end

    def mirror(entity, uploader)
      # using authors for git repo terminology consistency
      item = (entity == :authors) ? 'users' : entity.to_s
      download(item) do |data|
        case entity
        when :modules
          uploader.insert(:validations, flatten_validations(retrieve_validations(data)))
          data = flatten_modules(data)

          @itemizer.run!(data, uploader)
        when :releases
          data = flatten_releases(data)
        end

        uploader.insert(entity, data)
      end
    end

    def retrieve(entity, download = true)
      if download
        # I am focusing on authorship rather than just users, so for now I'm using the word authors
        item = (entity == :authors) ? 'users' : entity.to_s
        data = []
        download(item) do |resp|
          data.concat resp
        end
        save_json(entity, data)
      else
        data = File.read("#{@cachedir}/#{entity}.json")
      end

      case entity
      when :modules
        data = flatten_modules(data)
      when :releases
        data = flatten_releases(data)
      end
      save_nld_json(entity.to_s, data)
    end

    def retrieve_validations(modules, period = 25)
      results = {}

      begin
        offset   = 0
        endpoint = "/private/validations/"
        modules.each do |mod|
          name = "#{mod['owner']['username']}-#{mod['name']}"
          response = HTTParty.get("#{@forgeapi}#{endpoint}#{name}", headers: {'User-Agent' => @useragent})
          raise "Forge Error: #{@response.body}" unless response.code == 200

          results[name] = JSON.parse(response.body)
          offset       += 1

          if block_given? and (offset % period == 0)
            yield offset
            GC.start
          end
        end
      rescue => e
        $logger.error e.message
        $logger.debug e.backtrace.join("\n")
      end

      results
    end

    def validations()
      cache = "#{@cachedir}/modules.json"

      if File.exist? cache
        module_data = JSON.parse(File.read(cache))
      else
        module_data = retrieve(:modules)
      end

      begin
        spinner = TTY::Spinner.new("[:spinner] :title")
        spinner.update(title: "Downloading module validations ...")
        spinner.auto_spin

        results = retrieve_validations(module_data) do |offset|
          spinner.update(title: "Downloading module validations [#{offset}]...")
        end

        spinner.success('(OK)')
      rescue => e
        spinner.error('API error')
        $logger.error e.message
        $logger.debug e.backtrace.join("\n")
      end

      save_json('validations', results)
      save_nld_json('validations', flatten_validations(results))
      results
    end

    def download(entity)
       raise 'Please process downloaded data by passing a block' unless block_given?

      begin
        offset   = 0
        endpoint = "/v3/#{entity}?sort_by=downloads&limit=50"
        spinner  = TTY::Spinner.new("[:spinner] :title")
        spinner.update(title: "Downloading #{entity} ...")
        spinner.auto_spin

        while endpoint do
          response = HTTParty.get("#{@forgeapi}#{endpoint}", headers: {"User-Agent" => @useragent})
          raise "Forge Error: #{@response.body}" unless response.code == 200
          data = JSON.parse(response.body)

          offset  += 50
          endpoint = data['pagination']['next']

          yield munge_dates(data['results'])

          if (endpoint and (offset % 250 == 0))
            spinner.update(title: "Downloading #{entity} [#{offset}]...")
            GC.start
          end
        end

        spinner.success('(OK)')
      rescue => e
        spinner.error('API error')
        $logger.error e.message
        $logger.debug e.backtrace.join("\n")
      end

      nil
    end

    # transform dates into a format that bigquery knows
    def munge_dates(object)
      ["created_at", "updated_at", "deprecated_at", "deleted_at"].each do |field|
        next unless object.first.keys.include? field

        object.each do |record|
          next unless record[field]
          record[field] = DateTime.parse(record[field]).strftime("%Y-%m-%d %H:%M:%S")
        end
      end
      object
    end

    def save_json(thing, data)
      File.write("#{@cachedir}/#{thing}.json", data.to_json)
    end

    # store data in a way that bigquery can grok
    # uploading files is far easier than streaming data, when replacing a dataset
    def save_nld_json(thing, data)
      File.write("#{@cachedir}/nld_#{thing}.json", data.to_newline_delimited_json)
    end

    def flatten_modules(data)
      data.each do |row|
        row['owner']             = row['owner']['username']
        row['superseded_by']     = row['superseded_by']['slug'] rescue nil
        row['pdk']               = row['current_release']['pdk']
        row['supported']         = row['current_release']['supported']
        row['version']           = row['current_release']['version']
        row['validation_score']  = row['current_release']['validation_score']
        row['license']           = row['current_release']['metadata']['license']
        row['source']            = row['current_release']['metadata']['source']
        row['project_page']      = row['current_release']['metadata']['project_page']
        row['issues_url']        = row['current_release']['metadata']['issues_url']
        row['tasks']             = row['current_release']['tasks'].map{|task| task['name']} rescue []

        row['release_count']     = row['releases'].count rescue 0
        row['releases']          = row['releases'].map{|r| r['version']} rescue []

        simplify_metadata(row, row['current_release']['metadata'])
        row.delete('current_release')
      end
      data
    end

    def flatten_releases(data)
      data.each do |row|
        row['name']              = row['module']['name']
        row['owner']             = row['module']['owner']['username']
        row['license']           = row['metadata']['license']
        row['source']            = row['metadata']['source']
        row['project_page']      = row['metadata']['project_page']
        row['issues_url']        = row['metadata']['issues_url']
        row['tasks']             = row['tasks'].map{|task| task['name']} rescue []

        simplify_metadata(row, row['metadata'])
        row.delete('module')
      end
      data
    end

    def flatten_validations(data)
      data.map do |name, scores|
        row = { 'name' => name }
        scores.each do |entry|
          row[entry['name']] = entry['score']
        end
        row
      end
    end

    def simplify_metadata(data, metadata)
      data['operatingsystem']   = metadata['operatingsystem_support'].map{|i| i['operatingsystem']}                       rescue []
      data['dependencies']      = metadata['dependencies'].map{|i| i['name'].sub('/', '-')}                               rescue []
      data['puppet_range']      = metadata['requirements'].select{|r| r['name'] == 'puppet'}.first['version_requirement'] rescue nil
      data['metadata']          = metadata.to_json

      if data['puppet_range']
        range = SemanticPuppet::VersionRange.parse(data['puppet_range'])
        data['puppet_2x']       = range.include? SemanticPuppet::Version.parse('2.99.99')
        data['puppet_3x']       = range.include? SemanticPuppet::Version.parse('3.99.99')
        data['puppet_4x']       = range.include? SemanticPuppet::Version.parse('4.99.99')
        data['puppet_5x']       = range.include? SemanticPuppet::Version.parse('5.99.99')
        data['puppet_6x']       = range.include? SemanticPuppet::Version.parse('6.99.99')
        data['puppet_99x']      = range.include? SemanticPuppet::Version.parse('99.99.99')  # identify unbounded ranges
      end
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
