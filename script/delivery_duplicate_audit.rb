module DeliveryDuplicateAudit
  STOPWORDS = %w[
    de del la el los las y e con para por un una uno unas unos
  ].freeze

  Result = Struct.new(
    :delivery_id,
    :order_number,
    :delivery_date,
    :client_name,
    :items_count,
    :pairs,
    keyword_init: true
  )

  Pair = Struct.new(
    :delivery_item_a_id,
    :delivery_item_b_id,
    :order_item_id_a,
    :order_item_id_b,
    :order_item_id_diff,
    :product_a,
    :product_b,
    :score,
    :tokens_a,
    :tokens_b,
    keyword_init: true
  )

  class << self
    def run!(scope: Delivery.where("deliveries.id >= 5000"), min_score: 0.72, verbose: true)
      candidate_ids = scope.pluck(:id)

      puts "Deliveries candidatos (id >= 5000): #{candidate_ids.size}" if verbose

      results = []

      Delivery
        .where(id: candidate_ids)
        .includes(order: :client, delivery_items: :order_item)
        .find_each do |delivery|
        items = delivery.delivery_items.to_a
        next if items.size < 2

        pairs = suspicious_pairs(items, min_score: min_score)
        next if pairs.empty?

        results << Result.new(
          delivery_id: delivery.id,
          order_number: delivery.order.number,
          delivery_date: delivery.delivery_date,
          client_name: delivery.order.client.name,
          items_count: items.size,
          pairs: pairs
        )
      end

      print_report(results) if verbose
      puts
      puts "IDs sospechosos:"
      puts results.map(&:delivery_id).uniq.join(",")

      results
    end

    private

    def suspicious_pairs(items, min_score:)
      pairs = []

      items.combination(2).each do |a, b|
        product_a = a.order_item&.product.to_s.strip
        product_b = b.order_item&.product.to_s.strip

        next if product_a.blank? || product_b.blank?

        tokens_a = normalize_tokens(product_a)
        tokens_b = normalize_tokens(product_b)
        next if tokens_a.empty? || tokens_b.empty?

        score = similarity(tokens_a, tokens_b)
        id_diff = (a.order_item_id.to_i - b.order_item_id.to_i).abs

        next unless likely_duplicate?(tokens_a, tokens_b, score, min_score, a.order_item_id, b.order_item_id)

        pairs << Pair.new(
          delivery_item_a_id: a.id,
          delivery_item_b_id: b.id,
          order_item_id_a: a.order_item_id,
          order_item_id_b: b.order_item_id,
          order_item_id_diff: id_diff,
          product_a: product_a,
          product_b: product_b,
          score: score.round(3),
          tokens_a: tokens_a,
          tokens_b: tokens_b
        )
      end

      pairs.sort_by { |p| -p.order_item_id_diff }
    end

    def normalize_tokens(text)
      normalized = I18n.transliterate(text.to_s.downcase)
      normalized = normalized.gsub(/\A\d+\s+/, " ")
      normalized = normalized.gsub(/[^a-z0-9\s]/, " ")
      normalized = normalized.gsub(/\s+/, " ").strip

      tokens = normalized.split(" ")

      tokens.reject do |token|
        token.blank? || STOPWORDS.include?(token) || token.match?(/\A\d+\z/)
      end
    end

    def similarity(tokens_a, tokens_b)
      set_a = tokens_a.uniq
      set_b = tokens_b.uniq

      intersection = (set_a & set_b).size.to_f
      union = (set_a | set_b).size.to_f
      return 0.0 if union.zero?

      jaccard = intersection / union

      prefix_bonus =
        if set_a.first(2) == set_b.first(2) && set_a.first(2).present?
          0.15
        elsif set_a.first == set_b.first && set_a.first.present?
          0.08
        else
          0.0
        end

      [jaccard + prefix_bonus, 1.0].min
    end

    def likely_duplicate?(tokens_a, tokens_b, score, min_score, order_item_id_a, order_item_id_b)
      return false if order_item_id_a.nil? || order_item_id_b.nil?

      id_diff = (order_item_id_a - order_item_id_b).abs

      # Con diff grande, basta parecido moderado
      return true if id_diff > 100 && score >= min_score
      return true if id_diff > 100 && tokens_a == tokens_b
      return true if id_diff > 100 && (tokens_a & tokens_b).size >= 3

      # Sin diff grande, exigimos más
      return true if tokens_a == tokens_b

      shared = tokens_a & tokens_b
      min_size = [tokens_a.size, tokens_b.size].min
      return true if shared.size >= 3 && shared.size >= (min_size - 1)
      return true if score >= min_score

      false
    end

    def print_report(results)
      puts
      puts "=" * 120
      puts "DELIVERIES SOSPECHOSOS DE DUPLICACIÓN"
      puts "=" * 120
      puts "Total sospechosos: #{results.size}"
      puts

      results.each do |result|
        puts "Delivery ##{result.delivery_id} | Pedido: #{result.order_number} | Fecha: #{result.delivery_date} | Cliente: #{result.client_name} | Items: #{result.items_count}"

        result.pairs.each do |pair|
          puts "  - score=#{pair.score} | order_item_id diff=#{pair.order_item_id_diff}"
          puts "    A(delivery_item=#{pair.delivery_item_a_id}, order_item=#{pair.order_item_id_a}): #{pair.product_a}"
          puts "    B(delivery_item=#{pair.delivery_item_b_id}, order_item=#{pair.order_item_id_b}): #{pair.product_b}"
        end

        puts
      end
    end
  end
end

scope = Delivery.where("deliveries.id >= 5000")
DeliveryDuplicateAudit.run!(scope: scope, min_score: 0.72)
