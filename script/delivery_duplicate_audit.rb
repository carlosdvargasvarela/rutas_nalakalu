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
    :id_diff,
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
        items = delivery.delivery_items
          .select { |di| di.order_item.present? && di.order_item.created_at >= Time.zone.parse("2026-05-04 00:00:00") }

        next if items.size < 2

        pairs = suspicious_pairs(items)
        next if pairs.empty?

        results << Result.new(
          delivery_id: delivery.id,
          order_number: delivery.order.number,
          delivery_date: delivery.delivery_date,
          client_name: delivery.order.client.name,
          items_count: delivery.delivery_items.size,
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
        oi_a = a.order_item
        oi_b = b.order_item

        next unless oi_a.present? && oi_b.present?

        id_diff = (oi_a.id - oi_b.id).abs
        next unless id_diff > 100

        # --- similitud de texto comentada por ahora ---
        # tokens_a = normalize_tokens(oi_a.product)
        # tokens_b = normalize_tokens(oi_b.product)
        # score = similarity(tokens_a, tokens_b)
        # next unless score >= 0.72

        pairs << Pair.new(
          delivery_item_a_id: a.id,
          delivery_item_b_id: b.id,
          order_item_a_id: oi_a.id,
          order_item_b_id: oi_b.id,
          product_a: oi_a.product.to_s,
          product_b: oi_b.product.to_s,
          id_diff: id_diff
        )
      end

      pairs.sort_by { |p| -p.id_diff }
    end

    def print_report(results)
      puts
      puts "=" * 120
      puts "DELIVERIES SOSPECHOSOS DE DUPLICACIÓN"
      puts "=" * 120
      puts "Total sospechosos: #{results.size}"
      puts

      results.each do |result|
        puts "Delivery ##{result.delivery_id} | Pedido: #{result.order_number} | Fecha: #{result.delivery_date} | Cliente: #{result.client_name} | Items totales: #{result.items_count}"

        result.pairs.each do |pair|
          puts "  - order_item diff=#{pair.id_diff}"
          puts "    A (order_item ##{pair.order_item_a_id}, delivery_item ##{pair.delivery_item_a_id}): #{pair.product_a}"
          puts "    B (order_item ##{pair.order_item_b_id}, delivery_item ##{pair.delivery_item_b_id}): #{pair.product_b}"
        end

        puts
      end
    end
  end
end

scope = Delivery.where("deliveries.id >= 5000")
DeliveryDuplicateAudit.run!(scope: scope)
