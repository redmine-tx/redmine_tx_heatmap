require 'digest'

module RedmineTxHeatmap
  class EstimationRule < ActiveRecord::Base
    self.table_name = 'tx_heatmap_estimation_rules'

    before_validation :assign_fingerprint

    validates :md, numericality: { greater_than: 0 }
    validates :fingerprint, presence: true, uniqueness: true

    scope :enabled, -> { where(:enabled => true) }

    SIGNATURE_FIELDS = [
      :owner_group_id,
      :tracker_id,
      :category_name_key,
      :category_label,
      :category_id,
      :prefix_signature,
      :title_template,
      :stage_token
    ].freeze

    def self.available?
      connection.data_source_exists?(table_name)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def self.fingerprint_for(attributes)
      IssueSignature.fingerprint(symbolize_keys(attributes))
    end

    def self.digest
      return 'no-table' unless available?

      maximum_updated_at = maximum(:updated_at)
      count_value = count
      Digest::SHA1.hexdigest("#{maximum_updated_at ? maximum_updated_at.to_i : 0}:#{count_value}")
    end

    def self.ordered_for_matching
      enabled.order(:priority => :asc, :updated_at => :desc).to_a.sort_by do |rule|
        [rule.priority.to_i, -rule.specificity]
      end
    end

    def self.signature_attributes(attributes)
      source = symbolize_keys(attributes)
      SIGNATURE_FIELDS.each_with_object({}) do |field, memo|
        memo[field] = source[field]
      end
    end

    def self.symbolize_keys(attributes)
      attributes.to_h.each_with_object({}) do |(key, value), memo|
        memo[key.to_sym] = value
      end
    end

    def signature_attributes
      self.class.signature_attributes(attributes)
    end

    def matches_signature?(signature)
      signature = self.class.symbolize_keys(signature)
      return false if owner_group_id.present? && owner_group_id.to_i != signature[:owner_group_id].to_i
      return false if tracker_id.present? && tracker_id.to_i != signature[:tracker_id].to_i
      return false if category_name_key.present? && category_name_key != signature[:category_name_key]
      return false if category_id.present? && category_id.to_i != signature[:category_id].to_i
      return false if prefix_signature.present? && prefix_signature != signature[:prefix_signature]
      if title_template.present?
        subject = signature[:normalized_subject].presence || signature[:title_template]
        template_matches = IssueSignature.title_template_matches?(title_template, subject)
        return false unless template_matches || title_template == signature[:title_template]
      end
      return false if stage_token.present? && stage_token != signature[:stage_token]

      true
    end

    def specificity
      [
        owner_group_id,
        tracker_id,
        category_name_key,
        category_id,
        prefix_signature,
        title_template,
        stage_token
      ].count(&:present?)
    end

    private

    def assign_fingerprint
      self.fingerprint = self.class.fingerprint_for(signature_attributes)
    end
  end
end
