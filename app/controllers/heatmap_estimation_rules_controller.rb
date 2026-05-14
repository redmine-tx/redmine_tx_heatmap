class HeatmapEstimationRulesController < ApplicationController
  layout 'admin'

  before_action :require_admin
  before_action :find_rule, :only => [:update, :enable, :disable]
  before_action :find_candidate, :only => [:approve, :reject]

  def index
    @rules = RedmineTxHeatmap::EstimationRule.available? ? RedmineTxHeatmap::EstimationRule.order(:priority, :id).to_a : []
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
    scope = RedmineTxHeatmap::EstimationCandidate.available? ? RedmineTxHeatmap::EstimationCandidate.order(:status, :confidence, :id) : RedmineTxHeatmap::EstimationCandidate.none
    scope = scope.where(:status => @status) if @status != 'all'
    scope = scope.where.not(:confidence => 'low') if @status == 'pending' && @hide_low
    @candidates = scope.to_a
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
    candidates = RedmineTxHeatmap::EstimationCandidate.pending.where(:id => ids).to_a

    if candidates.empty?
      flash[:error] = '승인할 대기 후보를 선택하세요.'
      return redirect_to candidates_redirect_options
    end

    RedmineTxHeatmap::EstimationCandidate.transaction do
      candidates.each(&:approve!)
    end

    flash[:notice] = "MD 추정 후보 #{candidates.length}건을 승인했습니다."
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
    options
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
