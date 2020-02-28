require 'json'
require 'histogram'
require 'ascii_charts'
require 'histogram/array'
require 'sparkr'

class Mvp
  class Stats
    def initialize(options = {})
      @cachedir    = options[:cachedir]
      @today       = Date.today
      @github_data = options[:github_data]
      @output_file = options[:output_file]
    end

    def load(entity)
      JSON.parse(File.read("#{@cachedir}/#{entity}.json"))
    end

    def draw_graph(series, width, title = nil)
      series.compact!
      width = [width, series.size].min
      graph = []
      (bins, freqs) = series.histogram(:bin_width => width)

      bins.each_with_index do |item, index|
        graph << [ item, freqs[index] ]
      end
      puts AsciiCharts::Cartesian.new(graph, :bar => true, :hide_zero => true, :title => title).draw
    end

    # TODO: improve this to discard outliers and slightly weight larger series
    def average(series)
      series.compact!
      return 0 if series.empty?

      series.inject(0.0) { |sum, el| sum + el } / series.size
    end

    def days_ago(datestr)
      @today - Date.parse(datestr)
    end

    def years_ago(datestr)
      days_ago(datestr)/365
    end

    def current_releases
      return @current_releases if @current_releases

      data_m  = load('modules').reject {|m| m['owner'] == 'puppetlabs' }
      data_r  = load('releases').reject {|m| m['owner'] == 'puppetlabs' }

      @current_releases = data_m.map {|mod|
        name = mod['slug']
        curr = mod['releases'].first

        data_r.find {|r| r['slug'] == "#{name}-#{curr}" }
      }.compact
    end

    def tally_author_info(releases, target, scope='module_count')
      # update the author records with the fields we need
      target.each do |author|
        author['release_dates'] = []
        author['scores']        = []
      end

      releases.each do |mod|
        username = mod['owner']
        score    = mod['validation_score']
        author   = target.select{|m| m['username'] == username}.first

        author['release_dates']  << mod['created_at']
        author['scores']         << score if score
      end

      target.each do |author|
        author['average']        = average(author['scores']).to_i
        author['impact']         = author['average'] * author[scope]
        author['newest_release'] = author['release_dates'].max_by {|r| Date.parse(r) }
        author['oldest_release'] = author['release_dates'].min_by {|r| Date.parse(r) }
      end
    end

    def authors()
      data     = load('authors').reject {|u| u['username'] == 'puppetlabs' }
      casual   = data.select {|u| (2...10).include? u['module_count'] }
      prolific = data.select {|u| u['module_count'] > 9}
      topmost  = data.sort_by {|u| u['module_count']}.reverse[0...20]
      releases = data.sort_by {|u| u['release_count']}.reverse[0...20]

      puts "* Prolific in this case is more than 9 released modules."

      draw_graph(casual.map {|u| u['module_count']},   1, 'Number of modules from casual authors')
      draw_graph(prolific.map {|u| u['module_count']}, 5, 'Number of modules from prolific authors')

      puts
      puts
      puts "Author Statistics:"
      puts "  └── Number of users:                                #{data.count}"
      puts "  └── Number who have never published a module:       #{data.select {|u| u['module_count'] == 0}.count}"
      puts "  └── Number who have published a single module:      #{data.select {|u| u['module_count'] == 1}.count}"
      puts "  └── Number who have published multiple modules:     #{data.select {|u| u['module_count']  > 1}.count}"
      puts "  └── Number who have published two modules:          #{data.select {|u| u['module_count'] == 2}.count}"
      puts "  └── Number who have published more than 5 modules:  #{data.select {|u| u['module_count']  > 5}.count}"
      puts "  └── Number who have published more than 10 modules: #{data.select {|u| u['module_count']  > 10}.count}"
      puts "  └── Number who have published more than 20 modules: #{data.select {|u| u['module_count']  > 20}.count}"
      puts "  └── Number who have published more than 30 modules: #{data.select {|u| u['module_count']  > 30}.count}"
      puts "  └── Number who have published more than 50 modules: #{data.select {|u| u['module_count']  > 50}.count}"

      puts
      puts "Top 20 prolific module authors by number of modules | number of releases:"
      topmost.each do |author|
        puts "  └── %-55s: %d | %d" % [ "#{author['display_name']} (#{author['username']})",
                                        author['module_count'],
                                        author['release_count'] ]
      end
      puts
      puts "Top 20 active module authors by number of releases | number of modules:"
      releases.each do |author|
        puts "  └── %-55s: %d | %d" % [ "#{author['display_name']} (#{author['username']})",
                                        author['release_count'],
                                        author['module_count'] ]
      end
    end

    def modules()
      data_m  = load('modules').reject {|m| m['owner'] == 'puppetlabs' }
      data_a  = load('authors').reject {|u| u['username'] == 'puppetlabs' or u['module_count'] == 0}

      current = current_releases

      tally_author_info(current, data_a, 'module_count')

      prolific  = data_a.select{|a| a['impact']>1000}.sort_by {|a| a['impact']}
      topmost   = data_a.sort_by {|a| a['impact']}.reverse[0...20]
      published = data_a.reject {|u| u['newest_release'].nil?}

      puts '* Validation score is a Forge ranking based on the scores of an individual module release.'
      puts "* I am defining impact as an author's average validation * the number of modules releases they've made / 100."
      puts "* Prolific in this case is impact > 100."

      draw_graph(current.map {|m| years_ago(m['created_at']).round(1)},       0.5, 'Age (in years) distribution by module')
      draw_graph(published.map {|m| years_ago(m['newest_release']).round(1)}, 0.5, "Distribution of author's newest module by years old")
      draw_graph(current.map {|m| m['validation_score']},      10, 'Validation score distribution by module')
      draw_graph(data_a.map {|a| average(a['scores']).to_i },  10, 'Validation score distribution by author')
      draw_graph(prolific.map {|a| a['impact']/100 },           5, 'Impact distribution by prolific authors')

      puts
      puts
      puts "Module Statistics:"
      puts "  └── Number of modules:                              #{data_m.count}"
      puts "  └── Modules less than a year old:                   #{current.select {|m| days_ago(m['created_at']) < 365}.count}"
      puts "  └── Modules more than a year old:                   #{current.select {|m| days_ago(m['created_at']) > 365}.count}"
      puts "  └── Modules more than two years old:                #{current.select {|m| years_ago(m['created_at']) > 2}.count}"
      puts "  └── Modules more than three years old:              #{current.select {|m| years_ago(m['created_at']) > 3}.count}"
      puts "  └── Modules more than four years old:               #{current.select {|m| years_ago(m['created_at']) > 4}.count}"
      puts "  └── Modules more than five years old:               #{current.select {|m| years_ago(m['created_at']) > 5}.count}"
      puts "  └── Authors with 'perfect' validation scores:       #{data_a.select {|u| average(u['scores']).to_i == 100}.count}"
      puts "  └── Authors who've released in the last year:       #{published.select {|u| days_ago(u['newest_release']) < 365}.count}"
      puts "  └── Authors with no outdated (1yr) modules:         #{published.select {|u| days_ago(u['oldest_release']) < 365}.count}"

      puts
      puts "Top 20 high impact module authors by impact | number of modules:"
      topmost.each do |author|
        puts "  └── %-55s: %d | %d" % [ "#{author['display_name']} (#{author['username']})",
                                        author['impact']/100,
                                        author['module_count'] ]
      end
    end

    def releases()
      data_r  = load('releases').reject {|m| m['owner'] == 'puppetlabs' }
      data_a  = load('authors').reject {|u| u['username'] == 'puppetlabs' or u['module_count'] == 0}

      tally_author_info(data_r, data_a, 'release_count')

      impactful = data_a.select{|a| a['impact']>5000}.sort_by {|a| a['impact']}
      topmost   = data_a.sort_by {|a| a['impact']}.reverse[0...20]
      published = data_a.reject {|u| u['newest_release'].nil?}
      multiple  = published.select {|u| u['module_count'] > 1}
      prolific  = published.select {|u| u['module_count'] > 9}
      current   = multiple.sort_by {|a| days_ago(a['oldest_release'])}[0...20]

      # Authors that used to be active, but don't seem to be any more
      faded = published.select do |author|
        count_old = author['release_dates'].select {|r| years_ago(r) > 2 }.count
        count_new = author['release_dates'].select {|r| years_ago(r) < 1.5 }.count

        (count_old > 25 and count_old > (50*count_new))
      end

      oldest = years_ago(faded.map { |u| u['release_dates']}.flatten.max_by {|r| days_ago(r) }).to_i
      faded.each do |author|
        author['annual_releases'] = []

        (1..oldest).each do |age|
          author['annual_releases'] << author['release_dates'].select {|r| years_ago(r).to_i == age }.count
        end
        author['annual_releases'].reverse!
      end

      puts '* Validation score is a Forge ranking based on the scores of an individual module release.'
      puts "* I am defining impact as an author's average validation * the number of modules releases they've made / 100."
      puts "* Prolific in this case is more than 9 released modules."

      draw_graph(data_a.map {|a| average(a['scores']).to_i }, 10, 'Validation score distribution by author')
      draw_graph(impactful.map {|a| a['impact']/100 },        50, 'Impact distribution by impactful authors')

      puts
      puts
      puts "Release Statistics:"
      puts "  └── Number of releases:                                       #{data_r.count}"
      puts "  └── Authors with no releases:                                 #{data_a.count - published.count}"
      puts "  └── Authors with only a single releases:                      #{published.count - multiple.count}"
      puts "  └── Authors with no releases in one year:                     #{published.select {|m| years_ago(m['newest_release']) >1}.count}"
      puts "  └── Authors with no releases in two years:                    #{published.select {|m| years_ago(m['newest_release']) >2}.count}"
      puts "  └── Authors with no releases in three years:                  #{published.select {|m| years_ago(m['newest_release']) >3}.count}"
      puts "  └── Authors with no releases in four years:                   #{published.select {|m| years_ago(m['newest_release']) >4}.count}"
      puts "  └── Authors with no releases in five years:                   #{published.select {|m| years_ago(m['newest_release']) >5}.count}"
      puts "  └── Authors with multiple releases, all newer than a month:   #{multiple.select {|u| days_ago(u['oldest_release']) < 30}.count}"
      puts "  └── Authors with multiple releases, all newer than 3 months:  #{multiple.select {|u| days_ago(u['oldest_release']) < 90}.count}"
      puts "  └── Authors with multiple releases, all newer than 6 months:  #{multiple.select {|u| days_ago(u['oldest_release']) < 180}.count}"
      puts "  └── Authors with multiple releases, all newer than a year:    #{multiple.select {|u| days_ago(u['oldest_release']) < 365}.count}"
      puts "  └── Prolific authors, with releases all newer than 3 months:  #{prolific.select {|u| days_ago(u['oldest_release']) < 90}.count}"
      puts "  └── Prolific authors, with releases all newer than 6 months:  #{prolific.select {|u| days_ago(u['oldest_release']) < 180}.count}"
      puts "  └── Prolific authors, with releases all newer than a year:    #{prolific.select {|u| days_ago(u['oldest_release']) < 365}.count}"
      puts "  └── Prolific authors, with releases all newer than 2 years:   #{prolific.select {|u| years_ago(u['oldest_release']) < 2}.count}"

      puts
      puts "Top 20 high impact module authors by impact | number of releases:"
      topmost.each do |author|
        puts "  └── %-55s: %d | %d" % [ "#{author['display_name']} (#{author['username']})",
                                        author['impact']/100,
                                        author['release_count'] ]
      end
      puts
      puts "Top 20 current module authors by oldest release | number of releases:"
      current.each do |author|
        puts "  └── %-55s: %s | %d" % [ "#{author['display_name']} (#{author['username']})",
                                        Date.parse(author['oldest_release']).strftime('%v'),
                                        author['release_count'] ]
      end
      puts
      puts "Authors who are no longer as active as they used to be:"
      faded.each do |author|
        puts "  └── %-55s: %s    %s" % [ "#{author['display_name']} (#{author['username']})",
                                        Sparkr.sparkline(author['annual_releases']),
                                        author['annual_releases'].to_s ]
      end
    end

    def relationships()
      data_a  = load('authors').reject {|u| u['username'] == 'puppetlabs' or u['module_count'] == 0}
      current = current_releases.dup

      current.each do |mod|
        mod['metadata'] = JSON.parse(mod['metadata'])
        mod['metadata']['dependants'] = []
      end
      current.each do |mod|
        mod['metadata']['dependencies'].each do |dependency|
          target = current.select {|m| m['metadata']['name'] == dependency['name'].sub('/','-')}.first
          next unless target

          target['metadata']['dependants']  <<  mod['metadata']['name']
        end
      end

      data_a.each { |a| a['dependants'] = [] }
      current.each do |mod|
        count  = mod['metadata']['dependants'].count
        next unless count > 0

        author = data_a.select{|m| m['username'] == mod['owner']}.first
        author['dependants'] << count
      end
      data_a.each { |a| a['average_dependants'] = average(a['dependants']) }

      top_mods  = current.sort_by {|m| m['metadata']['dependants'].count}.reverse[0...20]
      connected = data_a.sort_by {|a| a['average_dependants'] }.reverse[0...20]

      low_conn  = current.select {|m| (2..10).include?  m['metadata']['dependants'].count}
      high_conn = current.select {|m| m['metadata']['dependants'].count > 10}

      draw_graph(low_conn.map {|m| m['metadata']['dependants'].count },   1, 'Number of dependent modules for low connection modules')
      draw_graph(high_conn.map {|m| m['metadata']['dependants'].count }, 10, 'Number of dependent modules for high connection modules')
      draw_graph(connected.map {|a| a['average_dependants'].to_i }, 5, 'Average number of dependent modules by author')

      puts
      puts "Top 20 connected module authors by number of dependants | number of modules | number of releases:"
      connected.each do |author|
        puts "  └── %-55s: %s | %d | %d" % [ "#{author['display_name']} (#{author['username']})",
                                        author['average_dependants'].to_i,
                                        author['module_count'],
                                        author['release_count'] ]
      end
      puts
    end

    def github()
      require 'csv'
      require 'net/http'
      raise "Need to provide a data file to gather GitHub stats!" unless @github_data

      unfound = []
      modules = load('modules').map {|m| m['slug']}
      CSV.foreach(@github_data) do |row|
        repo, stars = row
        next unless repo =~ /^\w+\/\w+$/

        begin
          uri_path = "https://raw.githubusercontent.com/#{repo}/master/metadata.json"
          metadata = JSON.parse(Net::HTTP.get(URI.parse(uri_path)))

          unless modules.include? metadata['name'].sub('/', '-')
            repo_path = "https://github.com/#{repo}"
            unfound  << { :repo => repo_path, :stars => stars}
          end
        rescue => e
          puts "#{e.class} for #{uri_path}"
        end
      end

      # sort the list by number of stars, descending then alphabatize by repo
      unfound.sort! do |a, b|
        [b[:stars], a[:repo]] <=> [a[:stars], b[:repo]]
      end

      if @output_file
        CSV.open("outreach.csv", "w+") do |csv|
          unfound.each do |mod|
            csv << [ mod[:repo], mod[:stars] ]
          end
        end
      end

      puts "The following #{unfound.count} module repositories were not represented on the Forge:" unless unfound.empty?
      unfound.each do |mod|
        puts "  └── %-65s: %d" % [ mod[:repo], mod[:stars] ]
      end


    end

    def validations()
      puts 'No validations yet'
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
