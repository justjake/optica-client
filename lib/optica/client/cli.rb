require 'optparse'
require 'filecache'
require 'pathname'

require_relative './config'
require_relative './request'
require_relative './fetch_json'

module Optica
  module Client
    # Command-line interface
    class CLI
      # rate-limit when printing huge JSON to a tty
      TTY_TIMEOUT = 0.00001

      USER_PATH = Pathname.new('~/.optical').expand_path
      CONFIG_PATH = USER_PATH.join('config.yml')
      CACHE_ROOT = USER_PATH.join('cache').to_s

      ERR_NOT_FOUND = 4
      ERR_INVALID = 2

      # 15 min
      CACHE_MAX_AGE = 15 * 60

      def self.run(argv)
        new.run(argv)
      end

      attr_reader :fields, :verbose, :cache, :delete_cache

      def initialize
        @config = ::Optica::Client::Config.from_file(CONFIG_PATH)
        @host = nil
        @fields = []
        @outs = []
        @verbose = false
        @pretty = data_pipe.tty?
        @cache = ::FileCache.new(
          "requests",
          CACHE_ROOT,
          CACHE_MAX_AGE,
          1
        )
        @delete_cache = false
      end

      # Options for the CLI
      #
      # @return [OptionParser]
      def option_parser
        @option_parser ||= OptionParser.new do |o|
          o.banner = "Usage: optical [options] [FIELD=FILTER] [FIELD2=FILTER2...]"
          o.version = ::Optica::Client::VERSION

          o.separator ''
          o.separator <<-EOS
  Fetch host information from Optica, and cache it for 15 minutes.
  Output the fetched information as a JSON stream, suitable for processing with `jq`.

  FIELD: any optica field; see your optica host for availible fields
  FILTER: either a bare string, like "optica", or a regex string, like "/^(o|O)ptica?/"
          EOS

          o.separator ''
          o.separator 'Options:'

          o.on(
            '-s',
            '--select a,b,c',
            ::Array,
            'Retrieve the given fields, in addition to the defaults'
          ) do |fs|
            @fields.concat(fs)
          end

          o.on(
            '-a',
            '--all',
            'Retrieve all fields (default is just role,id,hostname)'
          ) do |all|
            @fields = nil if all
          end

          o.on(
            '-j',
            '--just a,b,c',
            ::Array,
            'Print just the given fields as tab-seperated strings, instead of outputting json. Implies selecting those fields.'
          ) do |outs|
            @outs.concat(outs)
            @fields.concat(outs)
          end

          o.on(
            '-v',
            '--verbose',
            'Print debug information to STDERR'
          ) do |v|
            @verbose = v
          end

          o.on('-p', "--pretty[=#{data_pipe.tty?}]", "Pretty-print JSON (default true when STDOUT is a TTY)") do |p|
            @pretty = p
          end

          o.on(
            '-r',
            '--refresh',
            'Delete cache before performing request.'
          ) do |r|
            @delete_cache = r
          end

          o.on(
            '-h',
            '--host URI',
            "Optica host (default #{@config.default_host.inspect})"
          ) do |host|
            @host = host
          end

          o.on(
            '-H URI',
            '--set-default-host URI',
            'Set the default optica host'
          ) do |h|
            # TODO: move to #run
            @host = h
            @config.default_host = h
            @config.write!
            log "set default host to #{h}"
          end

          o.separator ''
          o.separator 'Examples:'
          o.separator <<-EOS
  Retrieve all nodes with a role starting with "example-":
    optical role=/^example-/

  Retrieve all the nodes registered to a test optica instance:
    optical -h https://optica-test.example.com

  Retrieve all data about my nodes:
    optical --all launched_by=`whoami`

  SSH into the first matched node:
    ssh $(optical --just hostname role=example branch=jake-test | head -n 1)
          EOS
        end
      end

      # Run the CLI
      #
      # @param [Array<String>] argv Command-line args
      def run(argv)
        args = option_parser.parse(argv)

        begin
          filters = args.map { |arg| parse_filter(arg) }.reduce({}, :merge)
        rescue ArgumentError => err
          ui_pipe.puts err.message
          ui_pipe.puts ''
          ui_pipe.puts option_parser
          return ERR_INVALID
        end

        if host.nil?
          ui_pipe.puts 'No host given.'
          ui_pipe.puts 'Set the default with -H, or for the invocation with -h.'
          ui_pipe.puts ''
          ui_pipe.puts option_parser
          return ERR_INVALID
        end

        if @outs.any? && @verbose
          ui_pipe.puts "Will print only: #{@outs}"
        end

        manage_cache

        req = ::Optica::Client::Request.new(host).where(filters)
        if fields
          req.select(*fields)
        else
          req.select_all
        end

        json = fetch(req)
        output(json['nodes'])

        if json['nodes'].any?
          # happy!
          return 0
        else
          # none found
          return ERR_NOT_FOUND
        end
      end

      def fetch(req)
        log "URL:     #{req.root}"
        log "Filters: #{req.filters}"
        log "Fields:  #{req.select_all? ? '(all fields)' : req.fields.inspect}"
        log "GET      #{req.to_uri}"

        key = req.to_uri.to_s
        cache.get_or_set(key) do
          fetch_with_progress_bar(req.to_uri)
        end
      end

      def output(json)
        log "got #{json.size} entries"

        use_sleep = false
        if json.size >= 1000 && data_pipe.tty?
          log 'reducing output speed to allow Ctrl-C'
          use_sleep = true
        end

        json.each do |_ip, node|
          if @outs.any?
            string = node.values_at(*@outs.uniq).join("\t")
          else
            string = @pretty ? JSON.pretty_generate(node) : JSON.fast_generate(node)
          end
          data_pipe.puts string
          # easier Ctrl-C in Tmux
          sleep TTY_TIMEOUT if use_sleep
        end
      end

      def manage_cache
        # clean up expired stuff
        cache.purge

        if delete_cache
          log "deleting cache dir #{CACHE_ROOT}"
          FileUtils.rm_r(CACHE_ROOT)
        end
      end

      def fetch_with_progress_bar(uri)
        ::Optica::Client.fetch_json(uri) do |_chunk, ratio|
          view = "Download #{progress_bar(ratio)}"

          ui_pipe.print "\r#{view}"
          ui_pipe.print "\n" if ratio == 1.0
        end
      end

      # Returns a progress bar, as a string.
      #
      # Looks kinda like this:
      # [>>>>>            ] NN.NN%
      #
      # @return [String]
      def progress_bar(ratio)
        width = 40
        chars = (width * ratio).to_i
        start = '['
        fin = ']'
        done = '>' * chars
        to_do = ' ' * (width - chars)
        percent = format(' %.2f%', ratio * 100)
        start + done + to_do + fin + percent
      end

      # Parse a command-line argument into a single Optica filter.
      #
      # Filter types:
      # - exact string match: base case
      #     attribute=string
      #
      # - regex match: filter begins and ends with /
      #     attribute=/^[rR]egexp?/
      #
      # - array match: begins with [, ends with ]
      #     attribute=[one,two]
      #
      # @param string [String]
      # @return [Hash<String, Any>] a filter hash
      def parse_filter(string)
        unless string.include?('=')
          raise ArgumentError.new("Invalid filter: #{string.inspect}")
        end

        key, *values = string.split('=')
        value = values.join('=')

        # parse regex
        if value[0] == '/' && value[-1] == '/'
          return { key => /#{value[1...-1]}/ }
        end

        # parse array-like
        if value[0] == '[' && value[-1] == ']'
          return { key => value[1...-1].split(',') }
        end

        # just a string
        { key => value }
      end

      def host
        @host || @config.default_host
      end

      def log(msg)
        if verbose
          ui_pipe.puts(msg)
        end
      end

      def data_pipe
        $stdout
      end

      def ui_pipe
        $stderr
      end
    end
  end
end
