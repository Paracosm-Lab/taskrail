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

    def initialize(base_url:, bearer_token: ENV["STUPIDCLAW_SERVICE_TOKEN"])
      @base_url = base_url
      @bearer_token = bearer_token.to_s
    end

    def get_json(path)
      uri = URI.join(@base_url, path)
      request = Net::HTTP::Get.new(uri)
      apply_auth(request)
      parse_response(http_request(uri, request))
    end

    def post_json(path, body)
      uri = URI.join(@base_url, path)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.dump(body)
      apply_auth(request)

      parse_response(http_request(uri, request))
    end

    private

    def apply_auth(request)
      return if @bearer_token.empty?

      request["Authorization"] = "Bearer #{@bearer_token}"
    end

    def http_request(uri, request)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
    end

    def parse_response(response)
      unless response.is_a?(Net::HTTPSuccess)
        raise HttpError.new(status: response.code.to_i, body: response.body)
      end

      JSON.parse(response.body)
    end
  end
end
