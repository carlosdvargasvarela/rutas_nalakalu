module DeliveryDuplicateAudit
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
    :order_item_a_id,
    :order_item_b_id,
    :product_a,
    :product_b,
    keyword_init: true
  )

  class << self
    def run!(scope: Delivery.where("deliveries.id >= 5000"), verbose: true)
      candidate_ids = scope.pluck(:id)

      puts "Deliveries candidatos (id >= 5000): #{candidate_ids.size}" if verbose

      results = []

      Delivery
        .where(id: candidate_ids)
        .includes(order: :client, delivery_items: :order_item)
        .find_each do |delivery|

        items = delivery.delivery_items.to_a
        next if items.size < 2

        pairs = suspicious_pairs(items)
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

    def suspicious_pairs(items)
      pairs = []

      items.combination(2).each do |a, b|
        oi_a = a.order_item_id
        oi_b = b.order_item_id

        next if oi_a.nil? || oi_b.nil?

        # REGLA PRINCIPAL: diferencia de order_item_id >= 200
        next unless (oi_a - oi_b).abs >= 200

        # REGLAS DE SIMILITUD (comentadas por ahora)
        # product_a = a.order_item&.product.to_s.strip
        # product_b = b.order_item&.product.to_s.strip
        # tokens_a = normalize_tokens(product_a)
        # tokens_b = normalize_tokens(product_b)
        # score = similarity(tokens_a, tokens_b)
        # next unless likely_duplicate?(tokens_a, tokens_b, score, 0.72)

        pairs << Pair.new(
          delivery_item_a_id: a.id,
          delivery_item_b_id: b.id,
          order_item_a_id: oi_a,
          order_item_b_id: oi_b,
          product_a: a.order_item&.product.to_s.strip,
          product_b: b.order_item&.product.to_s.strip
        )
      end

      pairs
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
          puts "  Par sospechoso:"
          puts "    A -> delivery_item=#{pair.delivery_item_a_id} | order_item=#{pair.order_item_a_id} | #{pair.product_a}"
          puts "    B -> delivery_item=#{pair.delivery_item_b_id} | order_item=#{pair.order_item_b_id} | #{pair.product_b}"
          puts "    Diferencia order_item_id: #{(pair.order_item_a_id - pair.order_item_b_id).abs}"
        end

        puts
      end
    end
  end
end

scope = Delivery.where("deliveries.id >= 5000")
DeliveryDuplicateAudit.run!(scope: scope)