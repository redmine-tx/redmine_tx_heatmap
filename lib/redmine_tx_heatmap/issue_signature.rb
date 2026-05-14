require 'digest'

module RedmineTxHeatmap
  module IssueSignature
    SEPARATOR = "\x1f".freeze
    FINGERPRINT_FIELDS = [
      :owner_group_id,
      :tracker_id,
      :category_name_key,
      :prefix_signature,
      :title_template,
      :stage_token
    ].freeze

    module_function

    def build(issue, owner_group_id:)
      category = issue.category
      subject = normalize_text(issue.subject)

      {
        :owner_group_id => owner_group_id,
        :tracker_id => issue.tracker_id,
        :category_name_key => category_name_key(category.try(:name)),
        :category_label => category.try(:name),
        :category_id => issue.category_id,
        :prefix_signature => prefix_signature(subject),
        :title_template => title_template(subject),
        :stage_token => stage_token(subject),
        :normalized_subject => subject
      }
    end

    def fingerprint(attributes)
      Digest::SHA256.hexdigest(FINGERPRINT_FIELDS.map { |field| attributes[field].to_s }.join(SEPARATOR))
    end

    def category_name_key(name)
      normalize_text(name).downcase.gsub(/[[:space:]_\-\/]+/, ' ').presence
    end

    def prefix_signature(subject)
      text = normalize_text(subject)
      return nil if text.blank?

      colon_prefix = text.split(/[:：]/, 2).first.to_s.strip if text.match?(/[:：]/)
      return title_template(colon_prefix) if colon_prefix.present?

      prefixes = []
      rest = text.dup
      loop do
        match = rest.match(/\A(\[[^\]]+\]|\([^)]+\)|【[^】]+】|（[^）]+）)\s*/)
        break unless match

        prefixes << match[1].strip
        rest = match.post_match
      end

      prefixes.join.presence
    end

    def stage_token(subject)
      parts = normalize_text(subject).split(/[:：]/).map(&:strip)
      return nil unless parts.length > 1

      token = parts.last
      return nil if token.blank? || token.length > 40

      token
    end

    def title_template(subject)
      text = normalize_text(subject)
      return nil if text.blank?

      text = text.gsub(%r{https?://\S+}, '{slot}')
      text = slot_parenthesized_numeric_identifier(text)
      text = text.gsub(/"[^"]+"|'[^']+'/, '{slot}')
      text = text.gsub(/\b\d{4}[-.\/]\d{1,2}[-.\/]\d{1,2}\b/, '{slot}')
      text = slot_numeric_fragments(text)
      text = text.gsub(/\b[A-Z]+-\d+\b/i, '{slot}')
      text = text.gsub(/\b[0-9a-f]{7,}\b/i, '{slot}')
      text = text.gsub(/(?:\{slot\}\s*){2,}/, '{slot}')
      text.strip.presence
    end

    def slot_numeric_fragments(text)
      text.gsub(/\d+(?:\.\d+)?/, '{slot}')
    end

    def slot_parenthesized_numeric_identifier(text)
      name = '[^\s\[\]()\:]{1}[^\s\[\]()\:]{0,40}?'
      alias_part = '(?:\s*\([^\d()]{1,40}\))*'
      numeric_id = '\s*\(\d{3,}\)'
      pattern = /(^|[[:space:]])(#{name}#{alias_part}#{numeric_id})(?=$|[[:space:]])/

      text.gsub(pattern) { "#{Regexp.last_match(1)}{slot}" }
    end

    def title_template_matches?(template, subject)
      normalized_template = normalize_text(template)
      normalized_subject = normalize_text(subject)
      return false if normalized_template.blank? || normalized_subject.blank?
      return normalized_template == normalized_subject unless normalized_template.include?('{slot}')

      return true if compact_template_matches?(normalized_template, normalized_subject)

      target_tokens = tokenize_for_template(normalized_subject)
      cursor = 0

      normalized_template.split(/\{slot\}/).map { |part| tokenize_for_template(part) }.reject(&:empty?).all? do |part_tokens|
        found_at = index_of_subsequence(target_tokens, part_tokens, cursor)
        return false unless found_at

        cursor = found_at + part_tokens.length
        true
      end
    end

    def tokenize_for_template(value)
      normalize_text(value).scan(/\{slot\}|\[[^\]]+\]|[[:alnum:]_]+/u)
    end

    def body_tokens_for_template(value)
      tokens = tokenize_for_template(value)
      tokens.drop_while { |token| prefix_token?(token) }
    end

    def template_from_tokens(tokens)
      phrase = Array(tokens).join(' ').strip
      return nil if phrase.blank?

      "{slot} #{phrase} {slot}"
    end

    def prefix_token?(token)
      token.to_s.start_with?('[') && token.to_s.end_with?(']')
    end

    def variable_token?(token)
      text = token.to_s
      text == '{slot}' || text.match?(/\A\d+(?:\.\d+)?\z/)
    end

    def compact_template_matches?(template, subject)
      target = compact_template_key(subject)
      cursor = 0

      template.split(/\{slot\}/).map { |part| compact_template_key(part) }.reject(&:blank?).all? do |part|
        found_at = target.index(part, cursor)
        return false unless found_at

        cursor = found_at + part.length
        true
      end
    end

    def compact_template_key(value)
      tokenize_for_template(value).join.downcase
    end

    def index_of_subsequence(tokens, part_tokens, start_index = 0)
      return start_index if part_tokens.empty?
      return nil if tokens.empty? || part_tokens.length > tokens.length

      last_start = tokens.length - part_tokens.length
      index = start_index.to_i
      while index <= last_start
        return index if tokens[index, part_tokens.length] == part_tokens

        index += 1
      end

      nil
    end

    def normalize_text(value)
      text = value.to_s
      text = text.unicode_normalize(:nfkc) if text.respond_to?(:unicode_normalize)
      text = text.tr('【】', '[]')
      text = text.gsub(/\s+/, ' ').strip
      text = canonicalize_leading_prefix_tokens(text)
      text = normalize_punctuation_spacing(text)
      text.gsub(/\s+/, ' ').strip
    end

    def canonicalize_leading_prefix_tokens(text)
      prefixes = []
      rest = text.dup

      loop do
        match = rest.match(/\A(?:\s*)(\[[^\]]+\]|\([^)]+\))\s*/)
        break unless match

        prefixes << canonical_prefix_token(match[1])
        rest = match.post_match
      end

      return text if prefixes.empty?

      "#{prefixes.join} #{rest}".strip
    end

    def canonical_prefix_token(token)
      inner = token.to_s.sub(/\A[\[(]/, '').sub(/[\])]\z/, '')
      "[#{normalize_punctuation_spacing(inner).strip}]"
    end

    def normalize_punctuation_spacing(text)
      normalized = text.to_s
      normalized = normalized.gsub(/\s*([,])\s*/, '\1 ')
      normalized = normalized.gsub(/\s*:\s*(?!\/)/, ': ')
      normalized = normalized.gsub(/\[\s*/, '[').gsub(/\s*\]/, ']')
      normalized = normalized.gsub(/\(\s*/, '(').gsub(/\s*\)/, ')')
      normalized = normalized.gsub(/\]\s+\[/, '][')
      normalized = normalized.gsub(/\)\s+\(/, ')(')
      normalized = normalized.gsub(/\s*#\s*(?=\d)/, ' ')
      normalized
    end
  end
end
