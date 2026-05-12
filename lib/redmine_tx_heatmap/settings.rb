require 'digest'
require 'json'

module RedmineTxHeatmap
  class Settings
    attr_reader :raw

    def initialize(raw = nil)
      @raw = raw || Setting.plugin_redmine_tx_heatmap || {}
    end

    def target_group_ids
      return team_settings.display_group_ids if shared_team_settings?

      normalize_ids(@raw['target_group_ids'])
    end

    def target_groups
      return team_settings.display_groups if shared_team_settings?

      ids = target_group_ids
      return [] if ids.empty?

      groups = Group.where(:id => ids).to_a
      groups.sort_by { |group| ids.index(group.id) || ids.length }
    end

    def excluded_user_ids(group_id)
      return team_settings.excluded_user_ids(group_id) if shared_team_settings?

      by_group = @raw['excluded_user_ids_by_group'] || {}
      normalize_ids(by_group[group_id.to_s] || by_group[group_id.to_i])
    end

    def effective_users(group)
      return team_settings.effective_users(group) if shared_team_settings?

      excluded = excluded_user_ids(group.id)
      users = group.users.active.to_a
      users = users.reject { |user| excluded.include?(user.id) } if excluded.any?
      users.sort_by(&:name)
    end

    def room_name_for_group(group_id)
      return nil unless defined?(TxBaseHelper::TeamSettings)

      team_settings.room_name_for_group(group_id)
    end

    def team_settings_source
      shared_team_settings? ? :tx_base : :heatmap
    end

    def include_subprojects?
      truthy?(@raw['include_subprojects'])
    end

    def show_unmapped?
      truthy?(@raw['show_unmapped'], true)
    end

    def default_period_unit
      @raw['default_period_unit'].to_s == 'month' ? 'month' : 'week'
    end

    def default_months
      integer_value(@raw['default_months'], 12, 1, 36)
    end

    def default_weeks
      integer_value(@raw['default_weeks'], 12, 1, 52)
    end

    def default_period_count
      default_period_unit == 'month' ? default_months : default_weeks
    end

    def overtime_multiplier
      float_value(@raw['overtime_multiplier'], 1.25, 1.0, 3.0)
    end

    def estimate_rules
      rules = @raw['estimate_rules'] || []
      rules = rules.values if rules.is_a?(Hash)

      Array(rules).filter_map do |rule|
        next unless rule.is_a?(Hash)
        next unless truthy?(rule['enabled'], true)

        pattern = rule['pattern'].to_s.strip
        md = safe_float(rule['md'])
        next if pattern.blank? || md.nil? || md <= 0

        {
          :pattern => pattern,
          :md => md,
          :group_id => normalize_optional_id(rule['group_id']),
          :category_id => normalize_optional_id(rule['category_id'])
        }
      end
    end

    def digest
      Digest::SHA1.hexdigest(JSON.dump({
        :heatmap => @raw,
        :team_settings => team_settings.present? ? team_settings.digest : nil
      }))
    end

    private

    def team_settings
      @team_settings ||= TxBaseHelper::TeamSettings.new if defined?(TxBaseHelper::TeamSettings)
    end

    def shared_team_settings?
      team_settings.present? && team_settings.configured?
    end

    def normalize_ids(value)
      Array(value).flatten.map { |item| item.to_s.strip }.reject(&:blank?).map(&:to_i).uniq
    end

    def normalize_optional_id(value)
      text = value.to_s.strip
      return nil if text.blank?

      text.to_i
    end

    def integer_value(value, default, min, max)
      number = value.to_i
      number = default if number <= 0 && min > 0
      [[number, min].max, max].min
    end

    def float_value(value, default, min, max)
      number = safe_float(value) || default
      [[number, min].max, max].min
    end

    def safe_float(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def truthy?(value, default = false)
      return default if value.nil?

      %w[1 true yes on].include?(value.to_s)
    end
  end
end
