module HeatmapHelper
  HEATMAP_ISSUE_COLUMNS = [:id, :subject, :assigned_to, :fixed_version, :tx_heatmap_period, :tx_heatmap_md].freeze

  def heatmap_issue_columns
    HEATMAP_ISSUE_COLUMNS
  end

  def heatmap_issue_list_data(entries)
    values = {}
    sort_values = {}
    issues = Array(entries).filter_map do |entry|
      issue = @heatmap_issues_by_id[(entry[:id] || entry['id']).to_i]
      next unless issue

      values[issue.id] = {
        :tx_heatmap_period => heatmap_period_label(entry),
        :tx_heatmap_md => heatmap_md_label(entry)
      }
      sort_values[issue.id] = {
        :tx_heatmap_period => heatmap_period_sort_value(entry),
        :tx_heatmap_md => heatmap_md_sort_value(entry)
      }
      issue
    end

    {
      :issues => issues,
      :column_values => values,
      :column_sort_values => sort_values
    }
  end

  def heatmap_detail_panel_id(row_index, key)
    safe_key = key.to_s.gsub(/[^a-zA-Z0-9_-]/, '-')
    "txhm-detail-panel-#{row_index}-#{safe_key}"
  end

  private

  def heatmap_period_label(entry)
    start_date = entry[:start_date] || entry['start_date']
    due_date = entry[:due_date] || entry['due_date']

    if start_date.present? && due_date.present?
      "#{start_date} ~ #{due_date}"
    elsif start_date.present?
      "#{start_date} ~"
    elsif due_date.present?
      "~ #{due_date}"
    else
      '날짜 없음'
    end
  end

  def heatmap_md_label(entry)
    md = entry[:md] || entry['md']
    return '미산정' if md.blank?

    format('%.1f', md.to_f).sub(/\.0\z/, '')
  end

  def heatmap_period_sort_value(entry)
    start_date = entry[:start_date] || entry['start_date']
    due_date = entry[:due_date] || entry['due_date']
    [start_date, due_date].compact.first.to_s
  end

  def heatmap_md_sort_value(entry)
    md = entry[:md] || entry['md']
    md.present? ? md.to_f : -1
  end
end
