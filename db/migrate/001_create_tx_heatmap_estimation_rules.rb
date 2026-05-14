class CreateTxHeatmapEstimationRules < ActiveRecord::Migration[6.1]
  def change
    create_table :tx_heatmap_estimation_rules, options: mysql_utf8mb4_options do |t|
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 100
      t.integer :owner_group_id
      t.integer :tracker_id
      t.string :category_name_key, limit: 191
      t.string :category_label
      t.integer :category_id
      t.string :prefix_signature
      t.text :title_template
      t.string :stage_token
      t.decimal :md, precision: 10, scale: 2, null: false
      t.string :confidence, limit: 32
      t.string :source, limit: 32
      t.integer :sample_count
      t.decimal :median_md, precision: 10, scale: 2
      t.decimal :spread, precision: 10, scale: 4
      t.string :fingerprint, limit: 64, null: false
      t.text :note
      t.timestamps
    end

    add_index :tx_heatmap_estimation_rules, :enabled
    add_index :tx_heatmap_estimation_rules, :owner_group_id
    add_index :tx_heatmap_estimation_rules, :tracker_id
    add_index :tx_heatmap_estimation_rules, :category_name_key
    add_index :tx_heatmap_estimation_rules, :fingerprint, unique: true
  end

  private

  def mysql_utf8mb4_options
    return nil unless connection.adapter_name.to_s.downcase.include?('mysql')

    'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
  end
end
