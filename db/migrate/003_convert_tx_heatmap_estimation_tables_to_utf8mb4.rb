class ConvertTxHeatmapEstimationTablesToUtf8mb4 < ActiveRecord::Migration[6.1]
  TABLES = [
    :tx_heatmap_estimation_rules,
    :tx_heatmap_estimation_candidates
  ].freeze

  def up
    return unless mysql?

    normalize_indexed_string_lengths

    TABLES.each do |table|
      next unless table_exists?(table)

      execute <<~SQL.squish
        ALTER TABLE #{quote_table_name(table)}
        CONVERT TO CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_ci
      SQL
    end
  end

  def down
    # Intentionally irreversible: converting back may corrupt stored UTF-8 text.
  end

  private

  def normalize_indexed_string_lengths
    if table_exists?(:tx_heatmap_estimation_rules)
      change_column :tx_heatmap_estimation_rules, :category_name_key, :string, limit: 191
      change_column :tx_heatmap_estimation_rules, :confidence, :string, limit: 32
      change_column :tx_heatmap_estimation_rules, :source, :string, limit: 32
      change_column :tx_heatmap_estimation_rules, :fingerprint, :string, limit: 64, null: false
    end

    return unless table_exists?(:tx_heatmap_estimation_candidates)

    change_column :tx_heatmap_estimation_candidates, :category_name_key, :string, limit: 191
    change_column :tx_heatmap_estimation_candidates, :status, :string, limit: 32, null: false, default: 'pending'
    change_column :tx_heatmap_estimation_candidates, :confidence, :string, limit: 32
    change_column :tx_heatmap_estimation_candidates, :fingerprint, :string, limit: 64, null: false
  end

  def mysql?
    connection.adapter_name.to_s.downcase.include?('mysql')
  end
end
