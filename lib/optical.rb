require 'optical/version'
require 'uri'
require 'optparse'
require 'net/http'
require 'json'
require 'stringio'

module Optical
  def self.fetch_json(uri)
    io = StringIO.new

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      req = Net::HTTP::Get.new(uri)

      http.request(req) do |res|
        file_size = res['content-length'].to_i
        amount_downloaded = 0

        res.read_body do |chunk|
          io.write chunk
          amount_downloaded += chunk.size
          ratio = amount_downloaded.to_f / file_size
          view = "Download #{progress_view(ratio)} %.2f%" % (ratio * 100)
          clear = ' ' * view.length
          line = "\r#{clear}\r#{view}"
          $stderr.print(line)
        end
      end
    end

    $stderr.print("\n")

    JSON.parse(io.string)
  end

  def self.progress_view(percent)
    width = 40
    chars = (width * percent).to_i
    start = '['
    fin = ']'
    done = '>' * chars
    to_do = ' ' * (width - chars)
    start + done + to_do + fin
  end

  class Request
    def self.airbnb
      new('https://optica.d.musta.ch')
    end

    def initialize(root_url, given_opts = {})
      opts = {
        fields: [],
        filters: {},
        all_fields: false,
      }.merge(given_opts)

      @uri = URI(root_url)
      @fields = opts[:fields]
      @filters = opts[:filters]
      @all_fields = opts[:all_fields]
    end

    # returns the fields that will be fetched using this request, via the
    # /roles endpoint.
    #
    # @see https://github.com/airbnb/optica/blob/master/optica.rb#L15-L24

    # Add more requested fields.
    #
    # Only the requested fields will be returned in your optica query, if
    # using {#get_fields}
    def fields(*fields)
      @fields.concat(fields).uniq!
      self
    end

    # Get all the fields from matching nodes!
    #
    # @return self
    def all_fields!
      @all_fields = true
      self
    end

    # Add filters to this optica request
    #
    # Filters should be a hash of String => Constraint, where constraint is a
    # - regex (regex match)
    # - boolean (matches 1, true, or True)
    # - string (exact match)
    #
    # @param filters [Hash]
    # @return self
    def where(filters)
      @filters.merge!(filters)
      self
    end

    # @return [URI]
    def to_uri
      uri = @uri.dup
      uri.query = URI.encode_www_form(query_params)
      uri.path = '/roles' unless @all_fields
      uri
    end

    private

    # @return [String]
    def query_params
      params = {}
      @filters.each do |key, value|
        params[key.to_s] = filter_to_param(value)
      end
      if @fields.any? && !@all_fields
        params['_extra_fields'] = @fields.join(',')
      end
      params
    end

    def filter_to_param(value)
      case value
      when Regexp
        value.source
      else
        "^#{value.to_s}$"
      end
    end
  end

  # Command-line interface
  class CLI
    DEFAULT_HOST = 'https://optica.d.musta.ch'
    def self.run(argv)
      new.run(argv)
    end

    attr_reader :req

    def initialize
      @uri = nil
      @fields = nil
      @verbose = false
    end

    def option_parser
      OptionParser.new do |o|
        o.on(
          '-f',
          '--fields FIELDS',
          'Retrieve only the given fields, plus some defaults. Split on commas'
        ) do |fs|
          @fields = fs.split(',')
        end

        o.on('-h', '--host URI', "Optica host (default #{DEFAULT_HOST})") do |host|
          # just for validation really
          @uri = URI(host)
        end

        o.on('-v', '--verbose', 'Print debug information to STDERR') do |v|
          @verbose = v
        end
      end
    end

    def run(argv)
      args = option_parser.parse(argv)
      filters = args.map { |arg| parse_filter(arg) }.reduce({}, :merge)
      uri = @uri || 'https://optica.d.musta.ch'
      fields = @fields

      req = ::Optical::Request.new(uri).where(filters)
      if fields
        req.fields(fields)
      else
        req.all_fields!
      end

      if @verbose
        pipe = $stderr
        pipe.puts "URL:     #{uri}"
        pipe.puts "Filters: #{filters}"
        pipe.puts "Fields:  #{fields ? fields.inspect : '(all fields)'}"
        pipe.puts "GET      #{req.to_uri}"
      end

      json = ::Optical.fetch_json(req.to_uri)

      output_json(json)
    end

    def output_json(hash)
      pipe = $stdout
      hash['nodes'].each do |_ip, node|
        pipe.puts JSON.dump(node)
      end
    end

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
      return { key => value }
    end
  end
end
