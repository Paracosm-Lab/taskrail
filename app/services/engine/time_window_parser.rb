module Engine
  class TimeWindowParser
    class InvalidWindow < ArgumentError; end

    USAGE_HINT = "invalid since window; valid formats: 30m, 2h, 7d, today, yesterday, this-week"

    def self.parse(value)
      new(value).parse
    end

    def initialize(value, now: Time.zone.now)
      @value = value.to_s
      @now = now
    end

    def parse
      case @value
      when /\A(\d+)(m|h|d)\z/
        amount = Regexp.last_match(1).to_i
        unit = Regexp.last_match(2)
        @now - amount.public_send(duration_method(unit))
      when "today"
        utc_now.beginning_of_day.in_time_zone
      when "yesterday"
        (utc_now.beginning_of_day - 1.day).in_time_zone
      when "this-week"
        utc_now.beginning_of_week(:monday).in_time_zone
      else
        raise InvalidWindow, USAGE_HINT
      end
    end

    private

    def duration_method(unit)
      case unit
      when "m" then :minutes
      when "h" then :hours
      when "d" then :days
      end
    end

    def utc_now
      @now.utc
    end
  end
end
