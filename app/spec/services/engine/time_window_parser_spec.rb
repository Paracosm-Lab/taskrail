require "rails_helper"

RSpec.describe Engine::TimeWindowParser do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to Time.zone.parse("2026-05-05 14:00:00 UTC") do
      example.run
    end
  end

  it "parses minute hour and day durations relative to now" do
    expect(described_class.parse("30m")).to eq(Time.zone.parse("2026-05-05 13:30:00 UTC"))
    expect(described_class.parse("2h")).to eq(Time.zone.parse("2026-05-05 12:00:00 UTC"))
    expect(described_class.parse("7d")).to eq(Time.zone.parse("2026-04-28 14:00:00 UTC"))
  end

  it "parses UTC named windows" do
    expect(described_class.parse("today")).to eq(Time.utc(2026, 5, 5).in_time_zone)
    expect(described_class.parse("yesterday")).to eq(Time.utc(2026, 5, 4).in_time_zone)
    expect(described_class.parse("this-week")).to eq(Time.utc(2026, 5, 4).in_time_zone)
  end

  it "raises a usage hint for invalid windows" do
    expect { described_class.parse("last-hour") }.to raise_error(
      Engine::TimeWindowParser::InvalidWindow,
      /valid formats: 30m, 2h, 7d, today, yesterday, this-week/
    )
  end
end
