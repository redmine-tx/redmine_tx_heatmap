get 'heatmap/index', :to => 'heatmap#index'

resources :projects do
  get 'heatmap/detail', :to => 'heatmap#detail'
  get 'heatmap', :to => 'heatmap#index'
end
