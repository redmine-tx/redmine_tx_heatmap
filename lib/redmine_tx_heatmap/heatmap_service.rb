module RedmineTxHeatmap
  class HeatmapService
    HOURS_PER_MD = 8.0

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
      @estimate_rules = @settings.estimate_rules
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
                   .includes(:assigned_to, :category, :fixed_version, :project, :status, :tracker)
                   .left_outer_joins(:fixed_version)
                   .where(:project_id => project_ids)

      discarded_ids = IssueStatus.respond_to?(:discarded_ids) ? IssueStatus.discarded_ids : []
      scope = scope.where.not(:status_id => discarded_ids) if discarded_ids.any?

      clauses = []
      params = []

      clauses << '(issues.start_date IS NOT NULL AND issues.due_date IS NOT NULL AND issues.start_date <= ? AND issues.due_date >= ?)'
      params << @period_end << @period_start

      clauses << '(issues.start_date IS NULL AND issues.due_date IS NULL AND versions.effective_date BETWEEN ? AND ?)'
      params << @period_start << @period_end

      if @current_period_key
        clauses << '((issues.start_date IS NULL AND issues.due_date IS NOT NULL) OR (issues.start_date IS NOT NULL AND issues.due_date IS NULL))'
      end

      scope.where([clauses.join(' OR '), *params])
    end

    def project_ids
      return [@project.id] unless @include_subprojects

      @project.self_and_descendants.pluck(:id)
    end

    def group_id_for_issue(issue)
      assigned_to = issue.assigned_to
      return assigned_to.id if assigned_to.is_a?(Group) && @group_ids.include?(assigned_to.id)
      return @user_group_id[assigned_to.id] if assigned_to.is_a?(User)

      nil
    end

    def member_row_for_issue(issue, group_id)
      assigned_to = issue.assigned_to
      return nil unless group_id && assigned_to.is_a?(User)

      @member_rows[[group_id, assigned_to.id]]
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
      Calendar.business_days_by_period(date_from, date_to, @periods, @holidays).each do |period_key, days|
        cell = row[:periods][period_key]
        next unless cell

        add_issue_to_period(row, cell, issue, days.to_f, 'date_range')
      end
    end

    def aggregate_one_sided_issue(row, issue)
      return unless @current_period_key

      cell = row[:periods][@current_period_key]
      return unless cell

      md, source = estimated_md(issue, row[:group_id])
      add_issue_to_period(row, cell, issue, md, source || 'unknown')
    end

    def aggregate_undated_issue(row, issue)
      md, source = estimated_md(issue, row[:group_id])
      entry = issue_entry(issue, md, source || 'unknown')

      if md
        row[:undated_md] += md
        row[:total_md] += md
      else
        row[:undated_unknown_count] += 1
        row[:total_unknown_count] += 1
      end

      row[:undated_issues] << entry
    end

    def add_issue_to_period(row, cell, issue, md, source)
      entry = issue_entry(issue, md, source)

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
      hours = issue.estimated_hours.to_f
      return [hours / HOURS_PER_MD, 'estimated_hours'] if hours > 0

      rule = matching_estimate_rule(issue, group_id)
      return [rule[:md], 'regex_rule'] if rule

      [nil, nil]
    end

    def matching_estimate_rule(issue, group_id)
      subject = issue.subject.to_s
      category_id = issue.category_id

      @estimate_rules.find do |rule|
        next false if rule[:group_id] && rule[:group_id] != group_id
        next false if rule[:category_id] && rule[:category_id] != category_id

        begin
          Regexp.new(rule[:pattern], Regexp::IGNORECASE).match?(subject)
        rescue RegexpError
          false
        end
      end
    end

    def issue_entry(issue, md, source)
      {
        :id => issue.id,
        :subject => issue.subject,
        :project => issue.project.try(:name),
        :tracker => issue.tracker.try(:name),
        :status => issue.status.try(:name),
        :assignee => issue.assigned_to.try(:name),
        :category => issue.category.try(:name),
        :fixed_version => issue.fixed_version.try(:name),
        :start_date => issue.start_date,
        :due_date => issue.due_date,
        :estimated_hours => issue.estimated_hours,
        :md => md,
        :source => source
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
  end
end
