require "rails_helper"
require "json"
require "open3"
require "socket"

RSpec.describe "bin/stupidclaw" do
  def with_server(response_body = { ok: true })
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
        requests << { method: method, path: path, query: query_string, body: body }
        response = JSON.dump(response_body)
        socket.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{response.bytesize}\r\nConnection: close\r\n\r\n#{response}"
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

  def run_cli(api_url, *args)
    Open3.capture3({ "STUPIDCLAW_API_URL" => api_url }, Rails.root.join("bin/stupidclaw").to_s, *args)
  end

  it "submits a work item" do
    with_server({ id: "123" }) do |api_url, requests|
      _stdout, _stderr, status = run_cli(api_url, "submit", "--queue", "development", "--spec", "./spec.md", "--title", "Add calendar")

      expect(status).to be_success
      request = requests.pop
      expect(request[:method]).to eq("POST")
      expect(request[:path]).to eq("/api/v1/work_items")
      expect(JSON.parse(request[:body])).to include("queue" => "development", "spec_url" => "./spec.md", "title" => "Add calendar")
    end
  end

  it "maps read and lifecycle commands to API endpoints" do
    with_server do |api_url, requests|
      commands = [
        [["status", "abc"], "GET", "/api/v1/work_items/abc"],
        [["list", "--queue", "development", "--stage", "build"], "GET", "/api/v1/work_items"],
        [["answer", "abc", "Use bearer tokens"], "POST", "/api/v1/work_items/abc/answer"],
        [["retry", "abc"], "POST", "/api/v1/work_items/abc/retry"],
        [["cancel", "abc"], "POST", "/api/v1/work_items/abc/cancel"],
        [["queues"], "GET", "/api/v1/queues"],
        [["stages", "development"], "GET", "/api/v1/queues/development/stages"]
      ]

      commands.each do |args, expected_method, expected_path|
        _stdout, _stderr, status = run_cli(api_url, *args)
        expect(status).to be_success
        request = requests.pop
        expect(request[:method]).to eq(expected_method)
        expect(request[:path]).to eq(expected_path)
      end
    end
  end
end
