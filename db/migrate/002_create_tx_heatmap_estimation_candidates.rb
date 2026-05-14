class CreateTxHeatmapEstimationCandidates < ActiveRecord::Migration[6.1]
  def change
    create_table :tx_heatmap_estimation_candidates, options: mysql_utf8mb4_options do |t|
      t.integer :owner_group_id
      t.integer :tracker_id
      t.string :category_name_key, limit: 191
      t.string :category_label
      t.integer :category_id
      t.string :prefix_signature
      t.text :title_template
      t.string :stage_token
      t.string :status, limit: 32, null: false, default: 'pending'
      t.integer :sample_count, null: false, default: 0
      t.decimal :median_md, precision: 10, scale: 2
      t.decimal :p25_md, precision: 10, scale: 2
      t.decimal :p75_md, precision: 10, scale: 2
      t.decimal :dispersion, precision: 10, scale: 4
      t.string :confidence, limit: 32
      t.text :example_issue_ids
      t.text :stats_snapshot
      t.string :fingerprint, limit: 64, null: false
      t.timestamps
    end

    add_index :tx_heatmap_estimation_candidates, :status
    add_index :tx_heatmap_estimation_candidates, :owner_group_id
    add_index :tx_heatmap_estimation_candidates, :tracker_id
    add_index :tx_heatmap_estimation_candidates, :category_name_key
    add_index :tx_heatmap_estimation_candidates, :fingerprint, unique: true
  end

  private

  def mysql_utf8mb4_options
    return nil unless connection.adapter_name.to_s.downcase.include?('mysql')

    'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
  end
end
