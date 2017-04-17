require 'uri'

module Optica
  module Client
    # Request builds URIs to fetch data from Optica. There is no planned support
    # for posting data to Optica.
    #
    # By default a Request will request the minimum number of fields from Optica
    # to save on response size, using the /roles endpoint. Use the {#fields} or
    # {#all_fields!} methods to fetch more fields.
    #
    # Build your request, then submit it using your HTTP client of choice using
    # the {#to_uri} method.
    class Request
      # @param root_url [String] HTTP(S) URI root of your Optica instance.
      # @param given_opts [Hash] options
      # @option given_opts [Array<String>] :fields Additional fields to request.
      #   see also {#fields} and {#all_fields!}
      # @option given_opts [Hash] :filters Filters. See {#where}.
      # @option given_opts [Boolean] :all_fields (false) See {#all_fields!}
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

      def filters
        @filters.dup
      end

      def fields
        @fields.dup
      end

      # returns the fields that will be fetched using this request, via the
      # /roles endpoint.
      #
      # @see https://github.com/airbnb/optica/blob/master/optica.rb#L15-L24

      # Add more requested fields.
      #
      # @param fields [Array<String>]
      # @return self
      def select(*fields)
        @fields.concat(fields).uniq!
        self
      end

      # Request all fields. Overwrites any previously-requested fields.
      #
      # @return self
      def select_all
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

      def root
        @uri
      end

      def select_all?
        @all_fields
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

      # @return [String]
      def filter_to_param(value)
        case value
          when ::Regexp
            value.source
          else
            literal = ::Regexp.escape(value.to_s)
            "^#{literal}$"
        end
      end
    end
  end
end
