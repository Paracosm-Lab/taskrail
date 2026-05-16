require "net/http"

module Engine
  class SpecResolver
    class FetchError < StandardError; end

    def initialize(spec_url)
      @spec_url = spec_url
    end

    def resolve
      if absolute_file_path?
        File.read(@spec_url)
      elsif relative_file_path?
        File.read(Rails.root.join(@spec_url.delete_prefix("./")))
      elsif http_url?
        fetch_http
      else
        @spec_url
      end
    rescue Errno::ENOENT
      raise FetchError, "spec file not found: #{@spec_url}"
    rescue Errno::EACCES
      raise FetchError, "permission denied reading spec: #{@spec_url}"
    end

    private

    def absolute_file_path?
      @spec_url.start_with?("/")
    end

    def relative_file_path?
      @spec_url.start_with?("./")
    end

    def http_url?
      @spec_url.start_with?("http://", "https://")
    end

    def fetch_http
      uri = URI(@spec_url)
      response = Net::HTTP.get_response(uri)
      return response.body if response.is_a?(Net::HTTPSuccess)

      raise FetchError, "failed to fetch spec #{@spec_url}: #{response.code} #{response.message}"
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, EOFError => e
      raise FetchError, "network error fetching spec #{@spec_url}: #{e.message}"
    end
  end
end
