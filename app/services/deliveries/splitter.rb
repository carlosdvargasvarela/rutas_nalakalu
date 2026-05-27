module Deliveries
  class Splitter
    # target_dates: ["2026-06-05", "2026-06-10", "2026-06-15"]
    # splits_params: { "item_id" => { "0" => "4", "1" => "3" }, ... }
    #   key   = item id
    #   value = hash of { date_index => quantity }
    def initialize(delivery:, target_dates:, splits_params:, reason:, current_user:)
      @delivery      = delivery
      @target_dates  = target_dates.map { |d| safe_parse_date(d) }.compact
      @splits_params = splits_params
      @reason        = reason
      @current_user  = current_user
    end

    def call
      raise ArgumentError, "Debés definir al menos una fecha destino." if target_dates.empty?

      moves = build_moves
      raise ArgumentError, "No ingresaste cantidades para mover. Completá al menos una celda." if moves.empty?

      validate_moves!(moves)

      moved = 0
      ActiveRecord::Base.transaction do
        # Agrupar por item para procesar en secuencia y recargar entre llamadas
        moves.group_by { |m| m[:item_id] }.each do |_item_id, item_moves|
          item_moves.each do |move|
            item = move[:item].reload
            DeliveryItems::Rescheduler.new(
              delivery_item: item,
              params: {
                new_delivery:          "true",
                new_date:              move[:date].to_s,
                quantity_to_reschedule: move[:quantity].to_s,
                reason:                reason
              },
              current_user: current_user,
              notify:       false
            ).call
            moved += 1
          end
        end
      end

      moved
    rescue => e
      Rails.logger.error("❌ Error en Deliveries::Splitter: #{e.message}")
      raise
    end

    private

    attr_reader :delivery, :target_dates, :splits_params, :reason, :current_user

    def build_moves
      item_ids  = splits_params.keys.map(&:to_i)
      items_map = delivery.delivery_items
        .bulk_reschedulable
        .where(id: item_ids)
        .includes(:order_item)
        .index_by { |i| i.id.to_s }

      moves = []

      splits_params.each do |item_id, qty_by_index|
        item = items_map[item_id.to_s]
        next if item.nil?

        qty_by_index.each do |date_idx, qty_str|
          qty  = qty_str.to_i
          next if qty <= 0

          date = target_dates[date_idx.to_i]
          next if date.nil? || date == delivery.delivery_date

          moves << { item: item, item_id: item_id, date: date, quantity: qty }
        end
      end

      moves
    end

    def validate_moves!(moves)
      # Verificar que la suma por item no supere la cantidad original
      moves.group_by { |m| m[:item_id] }.each do |item_id, item_moves|
        item       = item_moves.first[:item]
        total_move = item_moves.sum { |m| m[:quantity] }
        original   = item.quantity_delivered.to_i

        if total_move > original
          raise ArgumentError,
            "El producto '#{item.product}' tiene #{original} unidades pero intentás mover #{total_move}. Revisá las cantidades."
        end
      end
    end

    def safe_parse_date(str)
      Date.parse(str.to_s)
    rescue ArgumentError
      nil
    end
  end
end
