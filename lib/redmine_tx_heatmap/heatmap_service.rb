module RedmineTxHeatmap
  class HeatmapService
    def initialize(project:, include_subprojects:, settings:, start_period: nil, end_period: nil, period_unit: 'week', start_month: nil, end_month: nil)
      @project = project
      @period_unit = Calendar.normalize_period_unit(period_unit)
      @start_period = start_period || start_month
      @end_period = end_period || end_month
      @include_subprojects = include_subprojects
      @settings = settings
      @periods = Calendar.periods_between(@start_period, @end_period, @period_unit)
      @period_start = @periods.first[:start_date]
      @period_end = @periods.last[:end_date]
      @holidays = Calendar.holiday_map(@period_start, @period_end)
      @current_period_key = current_period_key
      @issue_estimator = IssueEstimator.new(settings: @settings)
      @team_resolver = TeamResolver.new(settings: @settings)
    end

    def call
      prepare_rows
      aggregate_issues
      finalize_rows

      {
        :project => { :id => @project.id, :name => @project.name },
        :period => {
          :start_date => @period_start,
          :end_date => @period_end,
          :unit => @period_unit,
          :include_subprojects => @include_subprojects
        },
        :periods => @periods,
        :months => @periods,
        :groups => @rows.values,
        :totals => totals,
        :generated_at => Time.zone.now
      }
    end

    private

    def prepare_rows
      @target_groups = @settings.target_groups
      @group_ids = @target_groups.map(&:id)
      @user_group_id = {}
      @member_rows = {}
      @rows = {}

      @target_groups.each do |group|
        users = @settings.effective_users(group)
        users.each { |user| @user_group_id[user.id] ||= group.id }
        member_rows = users.map do |user|
          build_member_row(group.id, user).tap do |member_row|
            @member_rows[[group.id, user.id]] = member_row
          end
        end
        @rows[group.id] = build_row(group.id, group.name, users.length, @settings.room_name_for_group(group.id), member_rows)
      end

      @rows[:unmapped] = build_row(nil, '미매핑', 0, nil) if @target_groups.any? && @settings.show_unmapped?
    end

    def build_row(group_id, name, member_count, room_name, member_rows = [])
      periods = {}
      @periods.each do |period|
        business_days = Calendar.business_days(period[:start_date], period[:end_date], @holidays)
        periods[period[:key]] = {
          :key => period[:key],
          :label => period[:label],
          :md => 0.0,
          :capacity_md => (member_count * business_days).to_f,
          :load => 0.0,
          :unknown_count => 0,
          :issues => []
        }
      end

      {
        :group_id => group_id,
        :room_name => room_name,
        :name => name,
        :member_count => member_count,
        :members => member_rows,
        :periods => periods,
        :months => periods,
        :undated_md => 0.0,
        :undated_unknown_count => 0,
        :undated_issues => [],
        :total_md => 0.0,
        :total_capacity_md => periods.values.sum { |cell| cell[:capacity_md] },
        :total_unknown_count => 0
      }
    end

    def build_member_row(group_id, user)
      build_row(group_id, user.name, 1, nil).merge(
        :user_id => user.id,
        :login => user.login,
        :is_member => true
      )
    end

    def aggregate_issues
      issue_scope.find_each do |issue|
        group_id = group_id_for_issue(issue)
        row = group_id ? @rows[group_id] : @rows[:unmapped]
        next unless row

        aggregate_issue_to_row(row, issue)

        member_row = member_row_for_issue(issue, group_id)
        aggregate_issue_to_row(member_row, issue) if member_row
      end
    end

    def issue_scope
      scope = Issue.visible
                   .includes(*issue_preload_associations)
                   .left_outer_joins(:fixed_version)
                   .where(:project_id => project_ids)

      scope = IssueFilters.exclude_discarded(scope)
      scope = IssueFilters.exclude_bug_trackers(scope)

      clauses = []
      params = []

      clauses << '(issues.start_date IS NOT NULL AND issues.due_date IS NOT NULL AND issues.start_date <= ? AND issues.due_date >= ?)'
      params << @period_end << @period_start

      clauses << '(issues.start_date IS NULL AND issues.due_date IS NULL AND versions.effective_date >= ?)'
      params << @period_start

      clauses << '(issues.start_date IS NOT NULL AND issues.due_date IS NULL AND issues.start_date <= ?)'
      params << @period_end

      clauses << '(issues.start_date IS NULL AND issues.due_date IS NOT NULL AND issues.due_date >= ?)'
      params << @period_start

      scope.where([clauses.join(' OR '), *params])
    end

    def project_ids
      return [@project.id] unless @include_subprojects

      @project.self_and_descendants.pluck(:id)
    end

    def group_id_for_issue(issue)
      @team_resolver.planned_owner_group_id(issue)
    end

    def member_row_for_issue(issue, group_id)
      worker_id = @team_resolver.worker_id_for_issue(issue)
      return nil unless group_id && worker_id

      @member_rows[[group_id, worker_id]]
    end

    def aggregate_issue_to_row(row, issue)
      if full_date_issue?(issue)
        aggregate_full_date_issue(row, issue)
      elsif one_sided_date_issue?(issue)
        aggregate_one_sided_issue(row, issue)
      else
        aggregate_undated_issue(row, issue)
      end
    end

    def full_date_issue?(issue)
      issue.start_date.present? && issue.due_date.present?
    end

    def one_sided_date_issue?(issue)
      issue.start_date.present? ^ issue.due_date.present?
    end

    def aggregate_full_date_issue(row, issue)
      date_from, date_to = [issue.start_date, issue.due_date].minmax
      days_by_period = Calendar.business_days_by_period(date_from, date_to, @periods, @holidays)
      return if days_by_period.empty?

      estimate = estimated_md(issue, row[:group_id])
      if estimate.md
        distribute_dated_estimate(row, issue, days_by_period, estimate)
      else
        distribute_date_range_days(row, issue, days_by_period)
      end
    end

    def distribute_dated_estimate(row, issue, days_by_period, estimate)
      total_days = days_by_period.values.sum.to_f
      return unless total_days.positive?

      days_by_period.each do |period_key, days|
        cell = row[:periods][period_key]
        next unless cell

        period_md = estimate.md.to_f * (days.to_f / total_days)
        add_issue_to_period(row, cell, issue, period_md, estimate.source, estimate)
      end
    end

    def distribute_date_range_days(row, issue, days_by_period)
      days_by_period.each do |period_key, days|
        cell = row[:periods][period_key]
        next unless cell

        add_issue_to_period(row, cell, issue, days.to_f, 'date_range')
      end
    end

    def aggregate_one_sided_issue(row, issue)
      estimate = estimated_md(issue, row[:group_id])
      if issue.start_date.present?
        aggregate_anchored_issue(row, issue, issue.start_date, :forward, estimate)
      else
        aggregate_anchored_issue(row, issue, issue.due_date, :backward, estimate)
      end
    end

    def aggregate_undated_issue(row, issue)
      assumed_due_date = assumed_due_date_for_issue(issue)
      if assumed_due_date
        estimate = estimated_md(issue, row[:group_id])
        return aggregate_anchored_issue(row, issue, assumed_due_date, :backward, estimate)
      end

      estimate = estimated_md(issue, row[:group_id])
      md = estimate.md
      entry = issue_entry(issue, md, estimate.source || 'unknown', estimate)

      if md
        row[:undated_md] += md
        row[:total_md] += md
      else
        row[:undated_unknown_count] += 1
        row[:total_unknown_count] += 1
      end

      row[:undated_issues] << entry
    end

    def add_issue_to_period(row, cell, issue, md, source, estimate = nil)
      entry = issue_entry(issue, md, source, estimate)

      if md
        cell[:md] += md
        row[:total_md] += md
      else
        cell[:unknown_count] += 1
        row[:total_unknown_count] += 1
      end

      cell[:issues] << entry
    end

    def estimated_md(issue, group_id)
      @issue_estimator.estimate(issue, owner_group_id: group_id)
    end

    def aggregate_anchored_issue(row, issue, anchor_date, direction, estimate)
      return unless anchor_date

      md = estimate.md
      if md
        distribute_anchored_issue(row, issue, md.to_f, anchor_date, direction, estimate.source || 'unknown', estimate)
      else
        add_unknown_anchored_issue(row, issue, anchor_date, estimate)
      end
    end

    def distribute_anchored_issue(row, issue, md, anchor_date, direction, source, estimate)
      business_days_by_period = anchored_business_days_by_period(anchor_date, md, direction)
      return if business_days_by_period.empty?

      business_days_by_period.each do |period_key, period_md|
        cell = row[:periods][period_key]
        next unless cell

        add_issue_to_period(row, cell, issue, period_md, source, estimate)
      end
    end

    def add_unknown_anchored_issue(row, issue, anchor_date, estimate)
      period_key = anchored_period_key(anchor_date)
      return unless period_key

      cell = row[:periods][period_key]
      return unless cell

      add_issue_to_period(row, cell, issue, nil, 'unknown', estimate)
    end

    def anchored_business_days_by_period(anchor_date, md, direction)
      md = md.to_f
      return {} unless md.positive?

      totals = Hash.new(0.0)
      remaining = md

      cursor = anchor_date
      while remaining.positive? && cursor_within_period_window?(cursor, direction)
        if business_day_on?(cursor)
          portion = [remaining, 1.0].min
          add_anchored_md_to_totals(totals, cursor, portion)
          remaining -= portion
        end
        cursor += direction == :forward ? 1 : -1
      end

      totals
    end

    def add_anchored_md_to_totals(totals, date, md)
      return unless date >= @period_start && date <= @period_end

      totals[Calendar.period_key(date, @period_unit)] += md
    end

    def anchored_period_key(anchor_date)
      return nil unless anchor_date
      return nil if anchor_date < @period_start || anchor_date > @period_end

      Calendar.period_key(anchor_date, @period_unit)
    end

    def cursor_within_period_window?(date, direction)
      direction == :forward ? date <= @period_end : date >= @period_start
    end

    def assumed_due_date_for_issue(issue)
      issue.fixed_version.try(:effective_date)
    end

    def holiday_lookup
      @holiday_lookup ||= {}
    end

    def ensure_holidays_for_year(year)
      @holiday_years ||= {}
      return if @holiday_years[year]

      start_date = Date.new(year, 1, 1)
      end_date = Date.new(year, 12, 31)
      holiday_lookup.merge!(Calendar.holiday_map(start_date, end_date))
      @holiday_years[year] = true
    end

    def business_day_on?(date)
      ensure_holidays_for_year(date.year)
      return false if date.saturday? || date.sunday?

      !holiday_lookup.key?(date)
    end

    def issue_entry(issue, md, source, estimate = nil)
      {
        :id => issue.id,
        :subject => issue.subject,
        :project => issue.project.try(:name),
        :tracker => issue.tracker.try(:name),
        :status => issue.status.try(:name),
        :worker => display_worker_for_issue(issue).try(:name),
        :category => issue.category.try(:name),
        :fixed_version => issue.fixed_version.try(:name),
        :start_date => issue.start_date,
        :due_date => issue.due_date,
        :estimated_hours => issue.estimated_hours,
        :md => md,
        :source => source,
        :confidence => estimate.try(:confidence),
        :rule_id => estimate.try(:rule_id),
        :explanation => estimate.try(:explanation)
      }
    end

    def finalize_rows
      (@rows.values + @member_rows.values).uniq.each do |row|
        row[:periods].each_value do |cell|
          cell[:md] = cell[:md].round(2)
          capacity = cell[:capacity_md]
          cell[:load] = capacity.positive? ? (cell[:md] / capacity).round(4) : 0.0
        end
        row[:undated_md] = row[:undated_md].round(2)
        row[:total_md] = row[:total_md].round(2)
      end
    end

    def totals
      rows = @rows.values
      total_md = rows.sum { |row| row[:total_md].to_f }.round(2)
      total_capacity_md = rows.sum { |row| row[:total_capacity_md].to_f }.round(2)
      total_unknown_count = rows.sum { |row| row[:total_unknown_count].to_i }

      {
        :md => total_md,
        :capacity_md => total_capacity_md,
        :load => total_capacity_md.positive? ? (total_md / total_capacity_md).round(4) : 0.0,
        :unknown_count => total_unknown_count
      }
    end

    def current_period_key
      today = Date.today
      return nil unless today >= @period_start && today <= @period_end

      Calendar.period_key(today, @period_unit)
    end

    def issue_preload_associations
      associations = [:assigned_to, :category, :fixed_version, :project, :status, :tracker]
      associations << :worker if Issue.reflect_on_association(:worker)
      associations
    end

    def display_worker_for_issue(issue)
      worker = issue.worker if issue.respond_to?(:worker)
      worker || issue.assigned_to
    end
  end
end
