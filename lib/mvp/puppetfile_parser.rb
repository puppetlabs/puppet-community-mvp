class Mvp
  class PuppetfileParser
    def initialize(options = {})
      @modules = []
      @repo    = nil
    end

    def suitable?
      defined?(RubyVM::AbstractSyntaxTree)
    end

    def parse(repo)
      # This only works on Ruby 2.6+
      return unless suitable?

      begin
        root = RubyVM::AbstractSyntaxTree.parse(repo[:content])
      rescue SyntaxError => e
        $logger.warn "Syntax error in #{repo[:repo_name]}/Puppetfile"
        $logger.warn e.message
      end

      @repo    = repo
      @modules = []
      traverse(root)
      @modules.compact.map do |row|
        row[:repo_name] = repo[:repo_name]
        row[:md5]       = repo[:md5]
        row
      end
    end

    def add_module(name, args)
      unless name.is_a? String
        $logger.warn "Non string module name in #{@repo[:repo_name]}/Puppetfile"
        return nil
      end
      name.gsub!('/', '-')
      case args
      when String, Symbol, NilClass
        @modules << {
          :module  => name,
          :type    => :forge,
          :source  => :forge,
          :version => args,
        }
      when Hash
        @modules << parse_args(name, args)
      else
        $logger.warn "#{@repo[:repo_name]}/Puppetfile: Unknown format: mod('#{name}', #{args.inspect})"
      end
    end

    def parse_args(name, args)
      data = {:module => name}

      if args.include? :git
        data[:type]    = :git
        data[:source]  = args[:git]
        data[:version] = args[:ref] || args[:tag] || args[:commit] || args[:branch] || :latest
      elsif args.include? :svn
        data[:type]    = :svn
        data[:source]  = args[:svn]
        data[:version] = args[:rev] || args[:revision] || :latest
      elsif args.include? :boxen
        data[:type]    = :boxen
        data[:source]  = args[:repo]
        data[:version] = args[:version] || :latest
      else
        $logger.warn "#{@repo[:repo_name]}/Puppetfile: Unknown args format: mod('#{name}', #{args.inspect})"
        return nil
      end

      data
    end

    def traverse(node)
      begin
        if node.type == :FCALL
          name = node.children.first
          args = node.children.last.children.map do |item|
            next if item.nil?

            case item.type
            when :HASH
              Hash[*item.children.first.children.compact.map {|n| n.children.first }]
            else
              item.children.first
            end
          end.compact

          case name
          when :mod
            add_module(args.shift, args.shift)
          when :forge
            # noop
          when :moduledir
            # noop
          when :github
            # oh boxen, you so silly.
            # The order of the unpacking below *is* important.
            modname = args.shift
            version = args.shift
            data    = args.shift || {}

            # this is gross but I'm not sure I actually care right now.
            if (modname.is_a? String and [String, NilClass].include? version.class and data.is_a? Hash)
              data[:boxen]   = :boxen
              data[:version] = version
              add_module(modname, data)
            else
              $logger.warn "#{@repo[:repo_name]}/Puppetfile: malformed boxen"
            end
          else
            # Should we record unexpected Ruby code or just log it to stdout?
            args = args.map {|a| a.is_a?(String) ? "'#{a}'" : a}.join(', ')
            $logger.warn "#{@repo[:repo_name]}/Puppetfile: Unexpected invocation of #{name}(#{args})"
          end
        end

        node.children.each do |n|
          next unless n.is_a? RubyVM::AbstractSyntaxTree::Node

          traverse(n)
        end
      rescue => e
        puts e.message
      end
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
