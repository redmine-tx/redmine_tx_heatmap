get 'heatmap/index', :to => 'heatmap#index'
get 'heatmap/estimation_rules', :to => 'heatmap_estimation_rules#index'
patch 'heatmap/estimation_rules/:id', :to => 'heatmap_estimation_rules#update'
post 'heatmap/estimation_rules/:id/disable', :to => 'heatmap_estimation_rules#disable'
post 'heatmap/estimation_rules/:id/enable', :to => 'heatmap_estimation_rules#enable'
get 'heatmap/estimation_candidates', :to => 'heatmap_estimation_rules#candidates'
post 'heatmap/estimation_candidates/rebuild', :to => 'heatmap_estimation_rules#rebuild'
post 'heatmap/estimation_candidates/bulk_approve', :to => 'heatmap_estimation_rules#bulk_approve'
post 'heatmap/estimation_candidates/:id/approve', :to => 'heatmap_estimation_rules#approve'
post 'heatmap/estimation_candidates/:id/reject', :to => 'heatmap_estimation_rules#reject'

resources :projects do
  get 'heatmap/detail', :to => 'heatmap#detail'
  get 'heatmap', :to => 'heatmap#index'
end
