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

      [:authors, :modules, :releases, :validations, :mirrors].each do |thing|
        next unless [:all, thing].include? target
        uploader.send(thing)
      end
    end

    def mirror(target = :all)
      retrieve(target)
      upload(target)
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
