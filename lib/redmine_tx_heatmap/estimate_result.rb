module RedmineTxHeatmap
  EstimateResult = Struct.new(:md, :source, :confidence, :rule_id, :explanation, keyword_init: true)
end
