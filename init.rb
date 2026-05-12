require 'redmine'

Redmine::Plugin.register :redmine_tx_heatmap do
  name 'Redmine Tx Heatmap'
  author 'KiHyun Kang'
  description 'Team workload heatmap for Redmine issues'
  version '0.0.1'

  requires_redmine_plugin :redmine_tx_0_base, :version_or_higher => '0.0.2'
  requires_redmine_plugin :redmine_tx_advanced_issue_status, :version_or_higher => '0.0.1'

  project_module :redmine_tx_heatmap do
    permission :view_heatmap, :heatmap => [:index, :detail]
  end

  menu :project_menu,
       :redmine_tx_heatmap,
       { :controller => 'heatmap', :action => 'index' },
       :caption => '히트맵',
       :param => :project_id,
       :after => :roadmap,
       :permission => :view_heatmap

  settings(
    :default => {
      'target_group_ids' => [],
      'excluded_user_ids_by_group' => {},
      'estimate_rules' => [],
      'include_subprojects' => '0',
      'default_period_unit' => 'week',
      'default_months' => '12',
      'default_weeks' => '12',
      'overtime_multiplier' => '1.25',
      'show_unmapped' => '1'
    },
    :partial => 'settings/redmine_tx_heatmap'
  )
end

Rails.application.config.after_initialize do
  require_dependency File.expand_path('lib/redmine_tx_heatmap/settings', __dir__)
  require_dependency File.expand_path('lib/redmine_tx_heatmap/calendar', __dir__)
  require_dependency File.expand_path('lib/redmine_tx_heatmap/heatmap_service', __dir__)
end
