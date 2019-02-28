class Mvp
  class PuppetfileParser
    def initialize(options = {})
      @modules = []
    end

    def parse(puppetfile)
      # This only works on Ruby 2.6+
      return unless defined?(RubyVM::AbstractSyntaxTree)

      root = RubyVM::AbstractSyntaxTree.parse(puppetfile)

      @modules = []
      traverse(root)
      @modules.compact
    end

    def add_module(name, args)
      case args
      when String, Symbol
        @modules << {
          :module  => name,
          :type    => :forge,
          :source  => :forge,
          :version => args,
        }
      when Hash
        @modules << parse_args(name, args)
      else
        $logger.warn "Unknown Puppetfile format: mod('#{name}', #{args.inspect})"
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
      else
        $logger.warn "Unknown Puppetfile format: mod('#{name}', #{args.inspect})"
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
          else
            # Should we record unexpected Ruby code or just log it to stdout?
            args = args.map {|a| a.is_a?(String) ? "'#{a}'" : a}.join(', ')
            $logger.warn "Unexpected invocation of #{name}(#{args})"
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
