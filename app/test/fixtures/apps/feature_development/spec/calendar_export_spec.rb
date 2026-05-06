require "time"
require_relative "../lib/calendar_export"

RSpec.describe CalendarExport do
  it "exports a VEVENT with DTSTART and SUMMARY" do
    event = described_class.new(title: "Launch", starts_at: Time.utc(2026, 5, 5, 12, 0, 0))

    output = event.to_ics

    expect(output).to include("BEGIN:VCALENDAR")
    expect(output).to include("BEGIN:VEVENT")
    expect(output).to include("DTSTART:20260505T120000Z")
    expect(output).to include("SUMMARY:Launch")
    expect(output).to include("END:VEVENT")
    expect(output).to include("END:VCALENDAR")
  end
end
