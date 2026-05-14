class HeatmapController < ApplicationController
  helper :heatmap

  menu_item :redmine_tx_heatmap
  layout 'base'

  before_action :require_login
  before_action :find_project
  before_action :authorize

  def index
    load_request_context
    @heatmap = fetch_heatmap
  end

  def detail
    load_request_context
    @heatmap = fetch_heatmap
    return render_404 unless params[:row_index].to_s =~ /\A\d+\z/

    @row_index = params[:row_index].to_i
    @row = Array(@heatmap[:groups])[@row_index]
    return render_404 unless @row
    @detail_row = @row
    if params[:member_user_id].present?
      return render_404 unless params[:member_user_id].to_s =~ /\A\d+\z/

      user_id = params[:member_user_id].to_i
      @detail_row = Array(@row[:members]).find { |member| member[:user_id].to_i == user_id }
      return render_404 unless @detail_row
    end

    if params[:undated] == '1'
      prepare_undated_detail
    else
      prepare_period_detail
    end

    return render_404 unless @detail_entries

    @heatmap_issues_by_id = preload_heatmap_issue_entries(@detail_entries)

    render :partial => 'detail', :layout => false
  end

  private

  def load_request_context
    @settings = RedmineTxHeatmap::Settings.new
    @period_unit = requested_period_unit
    @start_period = requested_start_period
    @end_period = requested_end_period(@start_period)
    @include_subprojects = requested_include_subprojects
  end

  def fetch_heatmap
    cache_key = [
      'redmine_tx_heatmap',
      @project.id,
      User.current.id,
      @period_unit,
      RedmineTxHeatmap::Calendar.period_key(@start_period, @period_unit),
      RedmineTxHeatmap::Calendar.period_key(@end_period, @period_unit),
      @include_subprojects ? 'with-subprojects' : 'project-only',
      @settings.digest,
      RedmineTxHeatmap::EstimationRule.digest
    ].join(':')

    Rails.cache.delete(cache_key) if params[:force] == 'true'

    Rails.cache.fetch(cache_key, :expires_in => 1.hour) do
      RedmineTxHeatmap::HeatmapService.new(
        :project => @project,
        :start_period => @start_period,
        :end_period => @end_period,
        :period_unit => @period_unit,
        :include_subprojects => @include_subprojects,
        :settings => @settings
      ).call
    end
  end

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def requested_period_unit
    RedmineTxHeatmap::Calendar.normalize_period_unit(params[:period_unit].presence || @settings.default_period_unit)
  end

  def requested_start_period
    parsed = RedmineTxHeatmap::Calendar.parse_period(params[:start_period].presence || params[:start_month], @period_unit)
    parsed || default_start_period
  end

  def requested_end_period(start_period)
    parsed = RedmineTxHeatmap::Calendar.parse_period(params[:end_period].presence || params[:end_month], @period_unit)
    return parsed if parsed && parsed >= start_period

    return default_end_period if period_params_blank?

    default_count = @period_unit == 'month' ? @settings.default_months : @settings.default_weeks
    RedmineTxHeatmap::Calendar.advance_period(start_period, @period_unit, [default_count, 1].max - 1)
  end

  def default_start_period
    RedmineTxHeatmap::Calendar.advance_period(current_period, @period_unit, -3)
  end

  def default_end_period
    RedmineTxHeatmap::Calendar.advance_period(current_period, @period_unit, 8)
  end

  def current_period
    RedmineTxHeatmap::Calendar.current_period_start(@period_unit)
  end

  def period_params_blank?
    params[:start_period].blank? && params[:end_period].blank? && params[:start_month].blank? && params[:end_month].blank?
  end

  def requested_include_subprojects
    return params[:include_subprojects] == '1' if params.key?(:include_subprojects)

    @settings.include_subprojects?
  end

  def prepare_period_detail
    @detail_key = params[:period_key].to_s
    periods = @heatmap[:periods] || @heatmap[:months] || []
    @detail_period = periods.find { |period| period[:key].to_s == @detail_key }
    return unless @detail_period

    cells = @detail_row[:periods] || @detail_row[:months] || {}
    @detail_cell = cells[@detail_key] || cells[@detail_key.to_sym]
    return unless @detail_cell

    @detail_title = "#{@detail_row[:name]} · #{@detail_period[:label]}"
    @detail_summary = "총 #{view_context.number_with_precision(@detail_cell[:md], :precision => 1, :strip_insignificant_zeros => true)} MD / 용량 #{view_context.number_with_precision(@detail_cell[:capacity_md], :precision => 1, :strip_insignificant_zeros => true)} MD / 부하 #{view_context.number_to_percentage(@detail_cell[:load].to_f * 100, :precision => 0)}"
    @detail_entries = Array(@detail_cell[:issues])
  end

  def prepare_undated_detail
    @detail_key = 'undated'
    @detail_title = "#{@detail_row[:name]} · 날짜 없음"
    @detail_summary = "총 #{view_context.number_with_precision(@detail_row[:undated_md], :precision => 1, :strip_insignificant_zeros => true)} MD, 미산정 #{@detail_row[:undated_unknown_count].to_i}건"
    @detail_entries = Array(@detail_row[:undated_issues])
  end

  def preload_heatmap_issue_entries(entries)
    ids = Array(entries).map { |entry| entry[:id] || entry['id'] }.compact.map(&:to_i).uniq
    return {} if ids.empty?

    Issue.visible
         .includes(*heatmap_issue_preload_associations)
         .where(:id => ids)
         .index_by(&:id)
  end

  def heatmap_issue_preload_associations
    associations = [:assigned_to, :fixed_version, :priority, :project, :status, :tracker]
    associations << :worker if Issue.reflect_on_association(:worker)
    associations
  end
end
