require 'mvp/forge'
require 'mvp/bigquery'
require 'mvp/stats'
require 'mvp/itemizer'

require 'tty-spinner'

class Mvp
  class Runner
    def initialize(options = {})
      @cachedir = options[:cachedir]
      @debug    = options[:debug]
      @options  = options
    end

    def retrieve(target = :all, download = true)
      bigquery = Mvp::Bigquery.new(@options)

      begin
        [:authors, :modules, :releases, :validations].each do |thing|
          next unless [:all, thing].include? target
          spinner = mkspinner("Retrieving #{thing} ...")
          data = bigquery.retrieve(thing)
          save_json(thing, data)
          spinner.success('(OK)')
        end

      rescue => e
        spinner.error("API error: #{e.message}")
        $logger.error "API error: #{e.message}"
        $logger.debug e.backtrace.join("\n")
        sleep 10
      end
    end

    def mirror(target = :all)
      forge    = Mvp::Forge.new(@options)
      bigquery = Mvp::Bigquery.new(@options)
      itemizer = Mvp::Itemizer.new(@options)

      begin
        [:authors, :modules, :releases].each do |thing|
          next unless [:all, thing].include? target
          spinner = mkspinner("Mirroring #{thing}...")
          bigquery.truncate(thing)
          forge.retrieve(thing) do |data, offset|
            spinner.update(title: "Mirroring #{thing} [#{offset}]...")
            bigquery.insert(thing, data)
          end
          spinner.success('(OK)')
        end

        if [:all, :validations].include? target
          spinner = mkspinner("Mirroring validations...")
          modules = bigquery.get(:modules, [:slug])
          bigquery.truncate(:validations)
          forge.retrieve_validations(modules) do |data, offset|
            spinner.update(title: "Mirroring validations [#{offset}]...")
            bigquery.insert(:validations, data)
          end
          spinner.success('(OK)')
        end

        if [:all, :itemizations].include? target
          spinner = mkspinner("Itemizing modules...")
          bigquery.unitemized.each do |mod|
            spinner.update(title: "Itemizing [#{mod[:slug]}]...")
            rows = itemizer.itemized(mod)
            bigquery.delete(:itemized, :module, mod[:slug])
            bigquery.insert(:itemized, rows)
          end
          spinner.success('(OK)')
        end

        if [:all, :mirrors, :tables].include? target
          @options[:gcloud][:mirrors].each do |entity|
            spinner = mkspinner("Mirroring #{entity[:type]} #{entity[:name]} to BigQuery...")
            bigquery.mirror_table(entity)
            spinner.success('(OK)')
          end
        end

      rescue => e
        spinner.error("API error: #{e.message}")
        $logger.error "API error: #{e.message}"
        $logger.debug e.backtrace.join("\n")
        sleep 10
      end
    end

    def stats(target)
      stats = Mvp::Stats.new(@options)

      [:authors, :modules, :releases, :relationships, :github, :validations].each do |thing|
        next unless [:all, thing].include? target
        stats.send(thing)
      end
    end

    def mkspinner(title)
      spinner = TTY::Spinner.new("[:spinner] :title")
      spinner.update(title: title)
      spinner.auto_spin
      spinner
    end

    def save_json(thing, data)
      File.write("#{@cachedir}/#{thing}.json", data.to_json)
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
