require 'json'
require 'httparty'
require 'tty-spinner'
require 'semantic_puppet'
require 'mvp/monkeypatches'

class Mvp
  class Downloader
    def initialize(options = {})
      @cachedir = options[:cachedir]
      @forgeapi = options[:forgeapi] ||'https://forgeapi.puppet.com'
    end

    def retrieve(entity, download = true)
      if download
        # I am focusing on authorship rather than just users, so for now I'm using the word authors
        item = (entity == :authors) ? 'users' : entity.to_s
        data = download(item)
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

    def validations()
      results = {}
      cache   = "#{@cachedir}/modules.json"

      if File.exist? cache
        module_data = JSON.parse(File.read(cache))
      else
        module_data = retrieve(:modules)
      end

      begin
        offset   = 0
        endpoint = "/private/validations/"
        spinner  = TTY::Spinner.new("[:spinner] :title")
        spinner.update(title: "Downloading module validations ...")
        spinner.auto_spin

        module_data.each do |mod|
          name = "#{mod['owner']['username']}-#{mod['name']}"
          response = HTTParty.get("#{@forgeapi}#{endpoint}#{name}", headers: {"User-Agent" => "Puppet Community Stats Monitor"})
          raise "Forge Error: #{@response.body}" unless response.code == 200

          data          = JSON.parse(response.body)
          offset       += 1
          results[name] = data

          spinner.update(title: "Downloading module validations [#{offset}]...") if (offset % 25 == 0)
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
      results = []

      begin
        offset   = 0
        endpoint = "/v3/#{entity}?sort_by=downloads&limit=50"
        spinner  = TTY::Spinner.new("[:spinner] :title")
        spinner.update(title: "Downloading #{entity} ...")
        spinner.auto_spin

        while endpoint do
          response = HTTParty.get("#{@forgeapi}#{endpoint}", headers: {"User-Agent" => "Puppet Community Stats Monitor"})
          raise "Forge Error: #{@response.body}" unless response.code == 200

          data = JSON.parse(response.body)
          offset  += 50
          results += data['results']
          endpoint = data['pagination']['next']

          spinner.update(title: "Downloading #{entity} [#{offset}]...") if (endpoint and (offset % 250 == 0))
        end

        spinner.success('(OK)')
      rescue => e
        spinner.error('API error')
        $logger.error e.message
        $logger.debug e.backtrace.join("\n")
      end

      munge_dates(results)
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
        row['tasks']             = row['current_release']['tasks'].map{|task| task['name']}

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
        row['owner']             = row['module']['username']
        row['license']           = row['metadata']['license']
        row['source']            = row['metadata']['source']
        row['project_page']      = row['metadata']['project_page']
        row['issues_url']        = row['metadata']['issues_url']
        row['tasks']             = row['tasks'].map{|task| task['name']}

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
      data['operatingsystem']   = metadata['operatingsystem_support'].map{|i| i['operatingsystem']}                       rescue nil
      data['dependencies']      = metadata['dependencies'].map{|i| i['name']}                                             rescue nil
      data['puppet_range']      = metadata['requirements'].select{|r| r['name'] == 'puppet'}.first['version_requirement'] rescue nil
      data['metadata']          = metadata.to_json

      if data['puppet_range']
        range = SemanticPuppet::VersionRange.parse(data['puppet_range'])
        data['puppet_2x']       = range.include? SemanticPuppet::Version.parse('2.99.99')
        data['puppet_3x']       = range.include? SemanticPuppet::Version.parse('3.99.99')
        data['puppet_4x']       = range.include? SemanticPuppet::Version.parse('4.99.99')
        data['puppet_5x']       = range.include? SemanticPuppet::Version.parse('5.99.99')
        data['puppet_6x']       = range.include? SemanticPuppet::Version.parse('6.99.99')
      end
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
