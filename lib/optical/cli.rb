require 'optparse'
require 'filecache'

require_relative './request'
require_relative './fetch_json'

module Optical
  # Command-line interface
  class CLI
    DEFAULT_HOST = 'https://optica.d.musta.ch'.freeze

    # rate-limit when printing huge JSON to a tty
    TTY_TIMEOUT = 0.00001

    CACHE_ROOT = File.expand_path('~/.optical/cache')

    # 15 min
    CACHE_MAX_AGE = 15 * 60

    def self.run(argv)
      new.run(argv)
    end

    attr_reader :uri, :fields, :verbose, :cache, :max_age, :delete_cache

    def initialize
      @uri = DEFAULT_HOST
      @fields = nil
      @verbose = false
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
        o.on(
          '-f',
          '--fields FIELDS',
          'Retrieve only the given fields, plus some defaults. Split on commas'
        ) do |fs|
          @fields = fs.split(',')
        end

        o.on(
          '-h',
          '--host URI',
          "Optica host (default #{DEFAULT_HOST})"
        ) do |host|
          @uri = host
        end

        o.on(
          '-v',
          '--verbose',
          'Print debug information to STDERR'
        ) do |v|
          @verbose = v
        end

        o.on(
          '-r',
          '--refresh',
          'Delete cache before performing request'
        ) do |r|
          @delete_cache = r
        end
      end
    end

    # Run the CLI
    #
    # @param [Array<String>] argv Command-line args
    def run(argv)
      args = option_parser.parse(argv)
      filters = args.map { |arg| parse_filter(arg) }.reduce({}, :merge)

      manage_cache

      req = ::Optical::Request.new(uri).where(filters)
      if fields
        req.select(fields)
      else
        req.select_all
      end

      json = fetch(req)
      output(json['nodes'])
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
        data_pipe.puts JSON.dump(node)
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
      ::Optical.fetch_json(uri) do |_chunk, ratio|
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
