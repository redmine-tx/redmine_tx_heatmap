module RedmineTxHeatmap
  module IssueFilters
    module_function

    def exclude_discarded(scope)
      discarded_ids = IssueStatus.respond_to?(:discarded_ids) ? IssueStatus.discarded_ids : []
      discarded_ids.any? ? scope.where.not(:status_id => discarded_ids) : scope
    end

    def exclude_bug_trackers(scope)
      ids = bug_tracker_ids
      ids.any? ? scope.where.not(:tracker_id => ids) : scope
    end

    def bug_tracker_ids
      if Tracker.respond_to?(:bug_trackers_ids)
        return Array(Tracker.bug_trackers_ids).map(&:to_i).uniq
      end

      return [] unless Tracker.column_names.include?('is_bug')

      Tracker.where(:is_bug => true).pluck(:id)
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      []
    end
  end
end
