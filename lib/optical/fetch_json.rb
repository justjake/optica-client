require 'net/http'
require 'json'
require 'stringio'

module Optical
  # Fetch the JSON data at the given URI. Blocks.
  #
  # As data is received, yeilds the data chunk (a string) and the completion
  # ratio (a float).
  #
  # @return [Any] the parsed JSON
  def self.fetch_json(uri)
    io = StringIO.new

    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == 'https'
    ) do |http|
      req = Net::HTTP::Get.new(uri)

      http.request(req) do |res|
        file_size = res['content-length'].to_i
        downloaded = 0.0

        res.read_body do |chunk|
          io.write chunk
          downloaded += chunk.size
          ratio = downloaded / file_size
          yield(chunk, ratio) if block_given?
        end
      end
    end

    JSON.parse(io.string)
  end
end
