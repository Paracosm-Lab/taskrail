require "rails_helper"
require "json"
require "socket"

RSpec.describe Cli::TaskRailApiClient do
  def with_server(status: 200, response_body: { ok: true })
    requests = Queue.new
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      loop do
        socket = server.accept
        request_line = socket.gets&.strip
        headers = {}
        while (line = socket.gets)&.strip != ""
          key, value = line.split(":", 2)
          headers[key.downcase] = value.strip if key && value
        end
        body = socket.read(headers.fetch("content-length", "0").to_i)
        method, full_path, = request_line.split(" ")
        path, query_string = full_path.split("?", 2)
        requests << { method: method, path: path, query: query_string, body: body, headers: headers }
        response = JSON.dump(response_body)
        reason = status == 200 ? "OK" : "Error"
        socket.write "HTTP/1.1 #{status} #{reason}\r\nContent-Type: application/json\r\nContent-Length: #{response.bytesize}\r\nConnection: close\r\n\r\n#{response}"
        socket.close
      rescue IOError
        break
      end
    end

    yield "http://127.0.0.1:#{port}", requests
  ensure
    server&.close
    thread&.kill
    thread&.join
  end

  it "gets parsed JSON from API paths" do
    with_server(response_body: { queues: [{ slug: "development" }] }) do |api_url, requests|
      result = described_class.new(base_url: api_url).get_json("/api/v1/queues")

      expect(result).to eq("queues" => [{ "slug" => "development" }])
      request = requests.pop
      expect(request[:method]).to eq("GET")
      expect(request[:path]).to eq("/api/v1/queues")
    end
  end

  it "posts JSON request bodies and returns parsed JSON" do
    with_server(response_body: { id: 123 }) do |api_url, requests|
      result = described_class.new(base_url: api_url).post_json("/api/v1/work_items", { queue: "development" })

      expect(result).to eq("id" => 123)
      request = requests.pop
      expect(request[:method]).to eq("POST")
      expect(request[:path]).to eq("/api/v1/work_items")
      expect(request[:headers]["content-type"]).to eq("application/json")
      expect(JSON.parse(request[:body])).to eq("queue" => "development")
    end
  end

  it "uses TASKRAIL_API_TOKEN before the legacy service token" do
    stub_const("ENV", ENV.to_hash.merge(
      "TASKRAIL_API_TOKEN" => "pat-token",
      "TASKRAIL_SERVICE_TOKEN" => "service-token"
    ))

    with_server do |api_url, requests|
      described_class.new(base_url: api_url).get_json("/api/v1/queues")

      expect(requests.pop[:headers]["authorization"]).to eq("Bearer pat-token")
    end
  end

  it "falls back to TASKRAIL_SERVICE_TOKEN for legacy automation" do
    stub_const("ENV", ENV.to_hash.merge(
      "TASKRAIL_API_TOKEN" => "",
      "TASKRAIL_SERVICE_TOKEN" => "service-token"
    ))

    with_server do |api_url, requests|
      described_class.new(base_url: api_url).get_json("/api/v1/queues")

      expect(requests.pop[:headers]["authorization"]).to eq("Bearer service-token")
    end
  end

  it "raises an HTTP error for non-success responses" do
    with_server(status: 500, response_body: { error: "boom" }) do |api_url, _requests|
      expect {
        described_class.new(base_url: api_url).get_json("/api/v1/queues")
      }.to raise_error(Cli::TaskRailApiClient::HttpError) { |error|
        expect(error.status).to eq(500)
        expect(error.body).to include("boom")
      }
    end
  end
end
