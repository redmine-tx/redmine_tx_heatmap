module RedmineTxHeatmap
  class TitleTemplateMiner
    MIN_PHRASE_TOKENS = 2
    MAX_PHRASE_TOKENS = 8
    DEFAULT_MIN_SAMPLES = 4
    DEFAULT_MAX_TEMPLATES = 12

    def self.templates_for(subjects, min_samples: DEFAULT_MIN_SAMPLES, max_templates: DEFAULT_MAX_TEMPLATES)
      new(subjects).templates(min_samples: min_samples, max_templates: max_templates)
    end

    def initialize(subjects)
      @subjects = Array(subjects).map { |subject| IssueSignature.normalize_text(subject) }
      @token_sequences = @subjects.map { |subject| IssueSignature.body_tokens_for_template(subject) }
    end

    def templates(min_samples: DEFAULT_MIN_SAMPLES, max_templates: DEFAULT_MAX_TEMPLATES)
      minimum = [min_samples.to_i, 1].max
      phrases = phrase_supports.values.select { |entry| entry[:indexes].length >= minimum }
      phrases = maximal_phrases(phrases)
      phrases.sort_by! { |entry| [-entry[:indexes].length, -entry[:tokens].length, entry[:tokens].join(' ')] }

      phrases.first(max_templates.to_i).filter_map do |entry|
        template = IssueSignature.template_from_tokens(entry[:tokens])
        next if template.blank?

        {
          :template => template,
          :tokens => entry[:tokens],
          :indexes => entry[:indexes],
          :support => entry[:indexes].length
        }
      end
    end

    private

    def phrase_supports
      supports = {}

      @token_sequences.each_with_index do |tokens, subject_index|
        seen = {}
        max_size = [MAX_PHRASE_TOKENS, tokens.length].min

        (MIN_PHRASE_TOKENS..max_size).each do |size|
          tokens.each_cons(size) do |phrase_tokens|
            next unless useful_phrase?(phrase_tokens)

            key = phrase_tokens.join(IssueSignature::SEPARATOR)
            seen[key] = phrase_tokens
          end
        end

        seen.each do |key, phrase_tokens|
          supports[key] ||= { :tokens => phrase_tokens, :indexes => [] }
          supports[key][:indexes] << subject_index
        end
      end

      supports
    end

    def useful_phrase?(tokens)
      return false if tokens.length < MIN_PHRASE_TOKENS
      return false if tokens.any? { |token| IssueSignature.prefix_token?(token) }
      return false if tokens.any? { |token| IssueSignature.variable_token?(token) }

      tokens.any? { |token| token.length > 1 }
    end

    def maximal_phrases(phrases)
      phrases.reject do |candidate|
        phrases.any? do |other|
          next false if candidate.equal?(other)
          next false unless same_indexes?(candidate[:indexes], other[:indexes])
          next false unless other[:tokens].length > candidate[:tokens].length

          contains_contiguous_tokens?(other[:tokens], candidate[:tokens])
        end
      end
    end

    def same_indexes?(left, right)
      left.length == right.length && left.sort == right.sort
    end

    def contains_contiguous_tokens?(tokens, part_tokens)
      !!IssueSignature.index_of_subsequence(tokens, part_tokens)
    end
  end
end
