require 'date'

module RedmineTxHeatmap
  module Calendar
    module_function

    def normalize_period_unit(value)
      value.to_s == 'month' ? 'month' : 'week'
    end

    def parse_period(value, unit)
      normalize_period_unit(unit) == 'month' ? parse_month(value) : parse_week(value)
    end

    def period_key(date, unit)
      normalize_period_unit(unit) == 'month' ? month_key(date) : week_key(date)
    end

    def periods_between(start_period, end_period, unit)
      normalize_period_unit(unit) == 'month' ? months_between(start_period, end_period) : weeks_between(start_period, end_period)
    end

    def advance_period(date, unit, count)
      normalize_period_unit(unit) == 'month' ? date.next_month(count) : date + (count * 7)
    end

    def current_period_start(unit, date = Date.today)
      normalize_period_unit(unit) == 'month' ? Date.new(date.year, date.month, 1) : week_start(date)
    end

    def parse_month(value)
      text = value.to_s.strip
      return nil if text.blank?

      if text =~ /\A(\d{4})[-.\/](\d{1,2})\z/
        year = Regexp.last_match(1).to_i
        month = Regexp.last_match(2).to_i
        return Date.new(year, month, 1) if month.between?(1, 12)
      end

      nil
    rescue Date::Error
      nil
    end

    def parse_week(value)
      text = value.to_s.strip
      return nil if text.blank?

      if text =~ /\A(\d{4})-?W(\d{1,2})\z/i
        year = Regexp.last_match(1).to_i
        week = Regexp.last_match(2).to_i
        return Date.commercial(year, week, 1) if week.between?(1, 53)
      end

      if text =~ /\A\d{4}-\d{1,2}-\d{1,2}\z/
        return week_start(Date.parse(text))
      end

      nil
    rescue Date::Error
      nil
    end

    def month_key(date)
      date.strftime('%Y-%m')
    end

    def week_key(date)
      week_start(date).strftime('%G-W%V')
    end

    def month_label(date)
      date.strftime('%Y.%m')
    end

    def week_label(date)
      start_date = week_start(date)
      format('%02d-#%d', start_date.month, week_of_month(start_date))
    end

    def months_between(start_month, end_month)
      months = []
      cursor = Date.new(start_month.year, start_month.month, 1)
      last = Date.new(end_month.year, end_month.month, 1)

      while cursor <= last
        months << {
          :key => month_key(cursor),
          :label => month_label(cursor),
          :start_date => cursor,
          :end_date => cursor.next_month - 1
        }
        cursor = cursor.next_month
      end

      months
    end

    def weeks_between(start_week, end_week)
      weeks = []
      cursor = week_start(start_week)
      last = week_start(end_week)

      while cursor <= last
        weeks << {
          :key => week_key(cursor),
          :label => week_label(cursor),
          :title => "#{cursor.strftime('%Y-%m-%d')} ~ #{(cursor + 6).strftime('%Y-%m-%d')}",
          :start_date => cursor,
          :end_date => cursor + 6
        }
        cursor += 7
      end

      weeks
    end

    def holiday_map(start_date, end_date)
      return {} unless defined?(TxBaseHelper::HolidayApi)
      return {} unless TxBaseHelper::HolidayApi.available?

      raw = TxBaseHelper::HolidayApi.for_date_range(start_date, end_date)
      raw.each_with_object({}) do |(date, info), map|
        map[to_date(date)] = info
      end
    rescue StandardError
      {}
    end

    def business_days(start_date, end_date, holidays = nil)
      holidays ||= holiday_map(start_date, end_date)
      count = 0
      each_date(start_date, end_date) do |date|
        count += 1 if business_day?(date, holidays)
      end
      count
    end

    def business_days_by_month(start_date, end_date, months, holidays = nil)
      start_date, end_date = [start_date, end_date].minmax
      holidays ||= holiday_map(start_date, end_date)

      months.each_with_object({}) do |month, totals|
        from = [start_date, month[:start_date]].max
        to = [end_date, month[:end_date]].min
        next if from > to

        days = business_days(from, to, holidays)
        totals[month[:key]] = days if days > 0
      end
    end

    def business_days_by_period(start_date, end_date, periods, holidays = nil)
      start_date, end_date = [start_date, end_date].minmax
      holidays ||= holiday_map(start_date, end_date)

      periods.each_with_object({}) do |period, totals|
        from = [start_date, period[:start_date]].max
        to = [end_date, period[:end_date]].min
        next if from > to

        days = business_days(from, to, holidays)
        totals[period[:key]] = days if days > 0
      end
    end

    def business_day?(date, holidays)
      !date.saturday? && !date.sunday? && !holidays.key?(date)
    end

    def week_start(date)
      date - (date.cwday - 1)
    end

    def week_of_month(date)
      first_week_start = week_start(Date.new(date.year, date.month, 1))
      ((week_start(date) - first_week_start).to_i / 7) + 1
    end

    def each_date(start_date, end_date)
      cursor = start_date
      while cursor <= end_date
        yield cursor
        cursor += 1
      end
    end

    def to_date(value)
      return value if value.is_a?(Date)

      Date.parse(value.to_s)
    end
  end
end
