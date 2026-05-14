class HeatmapEstimationRulesController < ApplicationController
  layout 'admin'

  RULE_SORTS = {
    'id' => [:id],
    'enabled' => [:enabled, :id],
    'priority' => [:priority, :id],
    'condition' => [:owner_group_id, :tracker_id, :category_name_key, :prefix_signature, :title_template, :id],
    'md' => [:md, :id],
    'samples' => [:sample_count, :id],
    'confidence' => [:confidence, :id],
    'updated' => [:updated_at, :id]
  }.freeze

  CANDIDATE_SORTS = {
    'id' => [:id],
    'status' => [:status, :id],
    'condition' => [:owner_group_id, :tracker_id, :category_name_key, :prefix_signature, :title_template, :id],
    'median' => [:median_md, :id],
    'samples' => [:sample_count, :id],
    'dispersion' => [:dispersion, :id],
    'confidence' => [:confidence, :id]
  }.freeze

  before_action :require_admin
  before_action :find_rule, :only => [:update, :enable, :disable]
  before_action :find_candidate, :only => [:approve, :reject]
  helper_method :rule_sort_options, :candidate_sort_options, :candidates_redirect_options, :sort_indicator

  def index
    scope = RedmineTxHeatmap::EstimationRule.available? ? RedmineTxHeatmap::EstimationRule.all : RedmineTxHeatmap::EstimationRule.none
    @rules = apply_sort(scope, RULE_SORTS, 'priority').to_a
    @groups_by_id = Group.where(:id => @rules.map(&:owner_group_id).compact).index_by(&:id)
    @trackers_by_id = Tracker.where(:id => @rules.map(&:tracker_id).compact).index_by(&:id)
  end

  def update
    @rule.update!(rule_params)
    flash[:notice] = 'MD 추정 규칙을 저장했습니다.'
    redirect_to :action => 'index'
  end

  def disable
    @rule.update!(:enabled => false)
    flash[:notice] = 'MD 추정 규칙을 비활성화했습니다.'
    redirect_to :action => 'index'
  end

  def enable
    @rule.update!(:enabled => true)
    flash[:notice] = 'MD 추정 규칙을 활성화했습니다.'
    redirect_to :action => 'index'
  end

  def candidates
    @status = params[:status].presence || 'pending'
    @hide_low = params[:hide_low] == '1'
    scope = RedmineTxHeatmap::EstimationCandidate.available? ? RedmineTxHeatmap::EstimationCandidate.all : RedmineTxHeatmap::EstimationCandidate.none
    scope = scope.where(:status => @status) if @status != 'all'
    scope = scope.where.not(:confidence => 'low') if @status == 'pending' && @hide_low
    @candidates = apply_sort(scope, CANDIDATE_SORTS, 'id').to_a
    @groups_by_id = Group.where(:id => @candidates.map(&:owner_group_id).compact).index_by(&:id)
    @trackers_by_id = Tracker.where(:id => @candidates.map(&:tracker_id).compact).index_by(&:id)
    @issues_by_id = Issue.where(:id => @candidates.flat_map(&:example_ids).uniq).index_by(&:id)
  end

  def rebuild
    scope = recent_closed_issue_scope
    min_samples = params[:min_samples].presence || RedmineTxHeatmap::EstimationCandidateBuilder::DEFAULT_MIN_SAMPLES
    result = RedmineTxHeatmap::EstimationCandidateBuilder.rebuild(
      scope: scope,
      min_samples: min_samples.to_i,
      purge_unapproved: true
    )
    if result[:error].present?
      flash[:error] = result[:error]
    else
      flash[:notice] = "미승인 후보 #{result[:purged_count]}건을 삭제하고 MD 추정 후보 #{result[:persisted_count]}건을 생성했습니다. 스캔 #{result[:scanned]}건."
    end
    redirect_to :action => 'candidates'
  end

  def approve
    @candidate.approve!
    flash[:notice] = 'MD 추정 후보를 승인했습니다.'
    redirect_to :action => 'candidates'
  end

  def bulk_approve
    ids = Array(params[:candidate_ids]).map(&:to_i).select(&:positive?).uniq
    pending_count = RedmineTxHeatmap::EstimationCandidate.pending.where(:id => ids).count

    if pending_count.zero?
      flash[:error] = '승인할 대기 후보를 선택하세요.'
      return redirect_to candidates_redirect_options
    end

    result = RedmineTxHeatmap::EstimationCandidate.bulk_approve!(ids)
    if result[:failed].any?
      failed_ids = result[:failed].first(5).map { |failure| "##{failure[:id]}" }.join(', ')
      flash[:error] = "MD 추정 후보 #{result[:approved_count]}건을 승인했고 #{result[:failed].length}건은 실패했습니다. 실패: #{failed_ids}"
    else
      flash[:notice] = "MD 추정 후보 #{result[:approved_count]}건을 승인했습니다."
    end
    redirect_to candidates_redirect_options
  rescue StandardError => e
    Rails.logger.error("[redmine_tx_heatmap] bulk approve failed: #{e.class}: #{e.message}\n#{e.backtrace.first(20).join("\n")}")
    flash[:error] = "MD 추정 후보 일괄 승인에 실패했습니다: #{e.class}: #{e.message}"
    redirect_to candidates_redirect_options
  end

  def reject
    @candidate.reject!
    flash[:notice] = 'MD 추정 후보를 거절했습니다.'
    redirect_to :action => 'candidates'
  end

  private

  def find_rule
    @rule = RedmineTxHeatmap::EstimationRule.find(params[:id])
  end

  def find_candidate
    @candidate = RedmineTxHeatmap::EstimationCandidate.find(params[:id])
  end

  def candidates_redirect_options
    options = { :action => 'candidates', :status => params[:status].presence || 'pending' }
    options[:hide_low] = '1' if params[:hide_low] == '1'
    options[:sort] = params[:sort] if params[:sort].present?
    options[:direction] = params[:direction] if params[:direction].present?
    options
  end

  def apply_sort(scope, allowed_sorts, default_sort)
    @sort_key = allowed_sorts.key?(params[:sort].to_s) ? params[:sort].to_s : default_sort
    @sort_direction = params[:direction] == 'desc' ? 'desc' : 'asc'
    order = allowed_sorts.fetch(@sort_key).each_with_object({}) do |column, memo|
      memo[column] = @sort_direction.to_sym
    end

    scope.reorder(order)
  end

  def sort_options(sort_key)
    direction = (@sort_key == sort_key && @sort_direction == 'asc') ? 'desc' : 'asc'
    { :sort => sort_key, :direction => direction }
  end

  def rule_sort_options(sort_key)
    { :action => 'index' }.merge(sort_options(sort_key))
  end

  def candidate_sort_options(sort_key)
    options = { :action => 'candidates', :status => @status }.merge(sort_options(sort_key))
    options[:hide_low] = '1' if @hide_low
    options
  end

  def sort_indicator(sort_key)
    return '' unless @sort_key == sort_key

    @sort_direction == 'asc' ? ' ▲' : ' ▼'
  end

  def rule_params
    params.require(:rule).permit(
      :enabled,
      :priority,
      :owner_group_id,
      :tracker_id,
      :category_name_key,
      :category_label,
      :category_id,
      :prefix_signature,
      :title_template,
      :stage_token,
      :md,
      :confidence,
      :source,
      :sample_count,
      :median_md,
      :spread,
      :note
    )
  end

  def recent_closed_issue_scope
    scope = Issue.where('issues.updated_on >= ?', 24.months.ago)
    closed_ids = IssueStatus.where(:is_closed => true).pluck(:id)
    closed_ids.any? ? scope.where(:status_id => closed_ids) : scope
  end
end
