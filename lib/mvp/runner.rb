require 'mvp/forge'
require 'mvp/bigquery'
require 'mvp/stats'
require 'mvp/itemizer'
require 'mvp/puppetfile_parser'

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
      pfparser = Mvp::PuppetfileParser.new(@options)

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

        if [:all, :puppetfiles].include? target
          spinner = mkspinner("Analyzing Puppetfile module references...")
          if pfparser.suitable?
            pfparser.sources = bigquery.module_sources
            bigquery.puppetfiles.each do |repo|
              spinner.update(title: "Analyzing [#{repo[:repo_name]}/Puppetfile]...")
              rows = pfparser.parse(repo)
              bigquery.delete(:puppetfile_usage, :repo_name, repo[:repo_name], :github)
              bigquery.insert(:puppetfile_usage, rows, :github)
            end
            spinner.success('(OK)')
          else
            spinner.error("(Not functional on Ruby #{RUBY_VERSION})")
          end
        end

      rescue => e
        spinner.error("API error: #{e.message}")
        $logger.error "API error: #{e.message}"
        $logger.debug e.backtrace.join("\n")
        sleep 10
      end
    end

    def analyze
      raise "Output file #{@options[:output_file]} exists" if File.file? @options[:output_file]

      bigquery = Mvp::Bigquery.new(@options)
      itemizer = Mvp::Itemizer.new(@options)

      begin
        spinner = mkspinner("Analyzing modules...")
        modules = bigquery.get(:modules, [:owner, :name, :version, :downloads, :updated_at, :deprecated_at])
        modules = modules.sample(@options[:count]) if @options[:count]

        require 'csv'
        modules.each do |mod|
          spinner.stop if @options[:debug]
          csv_string = CSV.generate do |csv|
            rows = itemizer.analyze(mod, @options[:script], @options[:debug])
            rows&.each {|row| csv << row}
          end
          spinner.start if @options[:debug]
          next if csv_string.empty?

          spinner.update(title: mod[:name])
          File.write(@options[:output_file], csv_string, mode: 'a+')
        end

        spinner.success('(OK)')
      end
    end

    def stats(target)
      stats = Mvp::Stats.new(@options)

      [:authors, :modules, :releases, :relationships, :validations].each do |thing|
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
