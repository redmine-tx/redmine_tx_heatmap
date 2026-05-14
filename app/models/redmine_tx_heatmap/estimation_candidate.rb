require 'json'

module RedmineTxHeatmap
  class EstimationCandidate < ActiveRecord::Base
    self.table_name = 'tx_heatmap_estimation_candidates'

    before_validation :assign_fingerprint

    validates :fingerprint, presence: true, uniqueness: true
    validates :status, presence: true

    scope :pending, -> { where(:status => 'pending') }

    def self.available?
      connection.data_source_exists?(table_name)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def signature_attributes
      EstimationRule.signature_attributes(attributes)
    end

    def example_ids
      parse_json_array(example_issue_ids)
    end

    def stats
      parse_json_hash(stats_snapshot)
    end

    def approve!
      self.class.transaction do
        rule = EstimationRule.where(:fingerprint => fingerprint).first_or_initialize
        rule.assign_attributes(signature_attributes)
        rule.enabled = true
        rule.priority = 100 if rule.priority.blank?
        rule.md = median_md
        rule.confidence = confidence
        rule.source = 'candidate'
        rule.sample_count = sample_count
        rule.median_md = median_md
        rule.spread = dispersion
        rule.save!

        update!(:status => 'approved')
        rule
      end
    end

    def reject!
      update!(:status => 'rejected')
    end

    private

    def assign_fingerprint
      self.fingerprint = EstimationRule.fingerprint_for(signature_attributes)
    end

    def parse_json_array(value)
      parsed = JSON.parse(value.to_s)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end

    def parse_json_hash(value)
      parsed = JSON.parse(value.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end
