require 'json'
require 'httparty'
require 'tty-spinner'
require 'semantic_puppet'

class Mvp
  class Forge
    def initialize(options = {})
      @useragent = 'Puppet Community Stats Monitor'
      @forgeapi  = options[:forgeapi] ||'https://forgeapi.puppet.com'
    end

    def retrieve(entity)
      raise 'Please process downloaded data by passing a block' unless block_given?

      # using authors for git repo terminology consistency
      entity = :users if entity == :authors
      begin
        offset   = 0
        endpoint = "/v3/#{entity}?sort_by=downloads&limit=50"

        while endpoint do
          response = HTTParty.get("#{@forgeapi}#{endpoint}", headers: {"User-Agent" => @useragent})
          raise "Forge Error: #{@response.body}" unless response.code == 200
          data    = JSON.parse(response.body)
          results = munge_dates(data['results'])

          case entity
          when :modules
            results = flatten_modules(results)
          when :releases
            results = flatten_releases(results)
          end

          yield results, offset

          offset  += 50
          endpoint = data['pagination']['next']
          if (endpoint and (offset % 250 == 0))
            GC.start
          end
        end

      rescue => e
        $logger.error e.message
        $logger.debug e.backtrace.join("\n")
      end

      nil
    end

    def retrieve_validations(modules, period = 25)
      raise 'Please process validations by passing a block' unless block_given?

      offset = 0
      begin
        modules.each_slice(period) do |group|
          offset += period
          results = group.map { |mod| validations(mod[:slug]) }

          yield results, offset
          GC.start
        end
      rescue => e
        $logger.error e.message
        $logger.debug e.backtrace.join("\n")
      end

      nil
    end

    def validations(name)
      endpoint = "/private/validations/"
      response = HTTParty.get("#{@forgeapi}#{endpoint}#{name}", headers: {'User-Agent' => @useragent})
      raise "Forge Error: #{@response.body}" unless response.code == 200

      flatten_validations(name, JSON.parse(response.body))
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
        row['plans']             = row['current_release']['plans'].map{|task| task['name']} rescue []

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
        row['plans']             = row['plans'].map{|task| task['name']} rescue []

        simplify_metadata(row, row['metadata'])

        # These items are just too big to store in the table
        ['module', 'changelog', 'readme', 'reference'].each do |column|
          row.delete(column)
        end
      end
      data
    end

    def flatten_validations(name, scores)
      row = { 'name' => name }
      scores.each do |entry|
        row[entry['name']] = entry['score']
      end
      row
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
