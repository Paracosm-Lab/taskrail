require "json"
require "net/http"
require "uri"

module Cli
  class StupidClawApiClient
    class HttpError < StandardError
      attr_reader :status, :body

      def initialize(status:, body:)
        @status = status
        @body = body
        super("HTTP #{status}: #{body}")
      end
    end

    def initialize(base_url:)
      @base_url = base_url
    end

    def get_json(path)
      uri = URI.join(@base_url, path)
      parse_response(Net::HTTP.get_response(uri))
    end

    def post_json(path, body)
      uri = URI.join(@base_url, path)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.dump(body)

      parse_response(Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) })
    end

    private

    def parse_response(response)
      unless response.is_a?(Net::HTTPSuccess)
        raise HttpError.new(status: response.code.to_i, body: response.body)
      end

      JSON.parse(response.body)
    end
  end
end
