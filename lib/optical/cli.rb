require 'optparse'

require_relative './request'
require_relative './fetch_json'

module Optical
  # Command-line interface
  class CLI
    DEFAULT_HOST = 'https://optica.d.musta.ch'.freeze

    def self.run(argv)
      new.run(argv)
    end

    attr_reader :uri, :fields, :verbose

    def initialize
      @uri = DEFAULT_HOST
      @fields = nil
      @verbose = false
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
      end
    end

    # Run the CLI
    #
    # @param [Array<String>] argv Command-line args
    def run(argv)
      args = option_parser.parse(argv)
      filters = args.map { |arg| parse_filter(arg) }.reduce({}, :merge)

      req = ::Optical::Request.new(uri).where(filters)
      if fields
        req.fields(fields)
      else
        req.all_fields!
      end

      if verbose
        ui_pipe.puts "URL:     #{uri}"
        ui_pipe.puts "Filters: #{filters}"
        ui_pipe.puts "Fields:  #{fields ? fields.inspect : '(all fields)'}"
        ui_pipe.puts "GET      #{req.to_uri}"
      end

      json = ::Optical.fetch_json(req.to_uri)

      hash['nodes'].each do |_ip, node|
        data_pipe.puts JSON.dump(node)
      end
    end

    def fetch_with_progress_bar(uri)
      ::Optica.fetch_json(uri) do |_chunk, ratio|
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
    def progress_bar(percent)
      width = 40
      chars = (width * percent).to_i
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

    def data_pipe
      $stdout
    end

    def ui_pipe
      $stderr
    end
  end
end
