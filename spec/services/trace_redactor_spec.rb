require "rails_helper"

RSpec.describe TraceRedactor do
  it "redacts expanded sensitive metadata keys" do
    value = {
      "x-api-key" => "abc123",
      "aws_secret_access_key" => "aws-secret",
      "private_key" => "private",
      "stage_name" => "build"
    }

    expect(described_class.safe_metadata(value)).to eq(
      "x-api-key" => "[REDACTED]",
      "aws_secret_access_key" => "[REDACTED]",
      "private_key" => "[REDACTED]",
      "stage_name" => "build"
    )
  end

  it "redacts common inline secret string patterns" do
    expect(described_class.safe_summary("apikey=abc123")).to eq("apikey=[REDACTED]")
    expect(described_class.safe_summary("Authorization: Bearer sk-12345")).to eq("Authorization: Bearer [REDACTED]")
    expect(described_class.safe_summary("stage_name=build")).to eq("stage_name=build")
  end
end
