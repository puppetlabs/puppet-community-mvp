require 'mvp/downloader'
require 'mvp/uploader'
require 'mvp/stats'

class Mvp
  class Runner
    def initialize(options = {})
      @cachedir = options[:cachedir]
      @debug    = options[:debug]
      @options  = options
    end

    def retrieve(target = :all, download = true)
      downloader = Mvp::Downloader.new(@options)

      [:authors, :modules, :releases].each do |thing|
        next unless [:all, thing].include? target
        downloader.retrieve(thing, download)
      end

      if [:all, :validations].include? target
        downloader.validations()
      end
    end

    def upload(target = :all)
      uploader = Mvp::Uploader.new(@options)

      [:authors, :modules, :releases, :validations, :github_mirrors].each do |thing|
        next unless [:all, thing].include? target
        uploader.send(thing)
      end
    end

    def mirror(target = :all)
      downloader = Mvp::Downloader.new(@options)
      uploader   = Mvp::Uploader.new(@options)

      # validations are downloaded with modules
      [:authors, :modules, :releases].each do |thing|
        next unless [:all, thing].include? target
          uploader.truncate(thing)
          downloader.mirror(thing, uploader)
      end

      if [:all, :mirrors].include? target
        uploader.github_mirrors()
      end
    end

    def stats(target)
      stats = Mvp::Stats.new(@options)

      [:authors, :modules, :releases, :relationships, :github, :validations].each do |thing|
        next unless [:all, thing].include? target
        stats.send(thing)
      end
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
