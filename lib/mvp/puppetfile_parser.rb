class Mvp
  class PuppetfileParser
    def initialize(options = {})
      @modules = {}
    end

    def parse(puppetfile)
      root = nil
      begin
        root = RubyVM::AbstractSyntaxTree.parse(puppetfile)
      rescue NameError => e
        # When run on Ruby 2.6 or greater, this will parse the Puppetfile directly.
        # See https://docs.ruby-lang.org/en/trunk/RubyVM/AbstractSyntaxTree.html for more infos
        raise R10K::Error.new("Cannot parse Puppetfile directly on Ruby version #{RUBY_VERSION}")
      end
      @modules = {}
      traverse(root)
    end

    def add_module(name, args)
      @modules[name] = args
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
            add_module(args.shift, *args)
          when :forge
            # noop
          when :moduledir
            # noop
          else
            # Should we log unexpected Ruby code?
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

    # Build a table with this schema
    # module | version | source | kind | element | count
    def table()
      modname      = data[:name]
      slug         = data[:slug]
      version      = data[:version]
      dependencies = data[:dependencies]

      itemized.map do |kind, elements|
        # the kind of element comes pluralized from puppet-itemize
        kind = kind.to_s
        kind = kind.end_with?('ses') ? kind.chomp('es') : kind.chomp('s')
        elements.map do |name, count|
          if name == modname
            depname = name
          else
            # This relies on a little guesswork.
            segments = name.split('::')                       # First see if its already namespaced and we can just use it
            segments = name.split('_') if segments.size == 1  # If not, then maybe it follows the pattern like 'mysql_password'
            depname  = segments.first
          end

          # There's a chance of collisions here. For example, if you depended on a module
          # named 'foobar-notify' and you used a 'notify' resource, then the resource would
          # be improperly linked to that module. That's a pretty small edge case though.
          source  = dependencies.find {|row| row.split('-').last == depname} rescue nil

          { :module => slug, :version => version, :source => source, :kind => kind, :element => name, :count => count }
        end
      end.flatten(1)
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
