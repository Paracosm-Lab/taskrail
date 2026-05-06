class CalendarExport
  def initialize(title:, starts_at:)
    @title = title
    @starts_at = starts_at
  end

  def to_ics
    "BEGIN:VCALENDAR\nSUMMARY:#{@title}\nEND:VCALENDAR\n"
  end
end
