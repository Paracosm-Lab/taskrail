require "rails_helper"

RSpec.describe Engine::SpecResolver do
  it "reads absolute file paths" do
    file = Tempfile.new("spec")
    file.write("hello spec")
    file.close

    expect(described_class.new(file.path).resolve).to eq("hello spec")
  ensure
    file&.unlink
  end

  it "reads relative dot-slash file paths from Rails root" do
    path = Rails.root.join("tmp/spec-resolver-test.md")
    File.write(path, "relative spec")

    expect(described_class.new("./tmp/spec-resolver-test.md").resolve).to eq("relative spec")
  ensure
    FileUtils.rm_f(path)
  end

  it "fetches http urls" do
    response = Net::HTTPSuccess.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return("remote spec")
    allow(Net::HTTP).to receive(:get_response).with(URI("https://example.com/spec.md")).and_return(response)

    expect(described_class.new("https://example.com/spec.md").resolve).to eq("remote spec")
  end

  it "raises when http fetching fails" do
    response = Net::HTTPNotFound.new("1.1", "404", "Not Found")
    allow(Net::HTTP).to receive(:get_response).with(URI("https://example.com/missing.md")).and_return(response)

    expect { described_class.new("https://example.com/missing.md").resolve }.to raise_error(Engine::SpecResolver::FetchError)
  end

  it "passes opaque spec URLs through unchanged" do
    expect(described_class.new("obsidian://note/taskrail").resolve).to eq("obsidian://note/taskrail")
  end

  it "raises FetchError for a missing absolute file path" do
    expect {
      described_class.new("/nonexistent/path/to/spec.md").resolve
    }.to raise_error(Engine::SpecResolver::FetchError, /not found/)
  end

  it "raises FetchError for a missing relative file path" do
    expect {
      described_class.new("./tmp/nonexistent-spec-resolver-test.md").resolve
    }.to raise_error(Engine::SpecResolver::FetchError)
  end

  it "raises FetchError when a network error occurs during HTTP fetch" do
    allow(Net::HTTP).to receive(:get_response).and_raise(SocketError, "Failed to open TCP connection")

    expect {
      described_class.new("https://example.com/spec.md").resolve
    }.to raise_error(Engine::SpecResolver::FetchError, /network error/)
  end
end
