module RedmineTxHeatmap
  class TeamResolver
    def initialize(settings: Settings.new)
      @settings = settings
    end

    def planned_owner_group(issue)
      group_for_principal(worker_for_issue(issue))
    end

    def planned_owner_group_id(issue)
      planned_owner_group(issue).try(:id)
    end

    def actual_owner_group(issue)
      planned_owner_group(issue)
    end

    def actual_owner_group_id(issue)
      actual_owner_group(issue).try(:id)
    end

    def worker_for_issue(issue)
      return issue.worker if issue.respond_to?(:worker) && issue.worker

      issue.assigned_to if issue.respond_to?(:assigned_to)
    end

    def worker_id_for_issue(issue)
      worker_for_issue(issue).try(:id)
    end

    private

    def group_for_principal(principal)
      return nil unless principal
      return principal if principal.is_a?(Group) && target_group_ids.include?(principal.id)
      return user_group(principal) if principal.is_a?(User)

      nil
    end

    def user_group(user)
      user_group_map[user.id]
    end

    def user_group_map
      @user_group_map ||= begin
        map = {}
        target_groups.each do |group|
          @settings.effective_users(group).each { |user| map[user.id] ||= group }
        end
        map
      end
    end

    def target_groups
      @target_groups ||= @settings.target_groups
    end

    def target_group_ids
      @target_group_ids ||= target_groups.map(&:id)
    end
  end
end
