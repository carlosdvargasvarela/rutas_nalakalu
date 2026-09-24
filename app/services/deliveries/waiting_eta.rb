module Deliveries
  # Minutos aproximados que le faltan al camión para llegar a cada parada
  # pendiente o en ruta de un plan, SIN exponer posición ni direcciones.
  # ponytail: distancia en línea recta × factor de calle / velocidad fija, sin
  # API de rutas. Si se necesita precisión, cambiar `travel_minutes` por Directions.
  class WaitingEta
    ROAD_FACTOR = 1.4
    AVG_SPEED_KMH = 30.0
    STOP_MINUTES = 10
    ROUND_TO = 5
    MAX_GPS_AGE = 15.minutes

    def initialize(assignment)
      @assignment = assignment
    end

    # @return [Integer, nil] nil si no hay GPS reciente o falta alguna coordenada
    def minutes
      self.class.for_plan(@assignment.delivery_plan)[@assignment.stop_order]
    end

    # @return [Hash{Integer=>Integer}] stop_order => minutos hasta llegar. Cada
    #   parada anterior suma su tiempo de servicio y el buffer de sus productos
    #   con palabra clave; las canceladas/reagendadas/archivadas/completadas no
    #   cuentan ni reciben ETA. Vacío si no hay GPS reciente.
    def self.for_plan(plan)
      return {} unless plan.current_lat && plan.last_seen_at && plan.last_seen_at > MAX_GPS_AGE.ago

      stops = plan.delivery_plan_assignments.where(status: %i[pending in_route]).where.not(stop_order: nil)
        .includes(delivery: [:delivery_address, {delivery_items: :order_item}]).to_a
        .reject { |a| a.delivery.hidden_from_route_map? }.group_by(&:stop_order).sort
      rules = buffer_rules
      from = [plan.current_lat.to_f, plan.current_lng.to_f]
      elapsed = 0.0
      stops.each_with_object({}) do |(order, group), result|
        addr = group.first.delivery.delivery_address
        to = [addr.latitude, addr.longitude]
        next if to.any?(&:nil?)

        to = to.map(&:to_f)
        elapsed += travel_minutes(from, to)
        result[order] = ((elapsed / ROUND_TO).ceil * ROUND_TO).clamp(ROUND_TO, nil)
        elapsed += STOP_MINUTES + group.sum { |a| buffer_minutes(a.delivery, rules) }
        from = to
      end
    end

    # 45 -> "45 minutos", 60 -> "1 hora", 90 -> "1 hora y 30 minutos"
    def self.humanize(mins)
      return "#{mins} minutos" if mins < 60

      h, m = mins.divmod(60)
      out = "#{h} #{(h == 1) ? "hora" : "horas"}"
      m.zero? ? out : "#{out} y #{m} minutos"
    end

    # Minutos extra por productos con palabra clave (p. ej. "armado=30"): por
    # producto, la mayor coincidencia.
    def self.buffer_minutes(delivery, rules = buffer_rules)
      delivery.delivery_items.sum do |item|
        text = Vocabulary.normalize(item.order_item.product)
        rules.filter_map { |kw, mins| mins if text.include?(kw) }.max.to_i
      end
    end

    def self.buffer_rules
      Vocabulary.detector_keywords("assembly_buffer").fetch("minutes", []).filter_map do |line|
        kw, mins = line.split("=", 2).map(&:strip)
        [kw, mins.to_i] if kw.present? && mins.to_i > 0
      end
    end

    def self.travel_minutes(a, b)
      rad = Math::PI / 180
      dlat = (b[0] - a[0]) * rad
      dlng = (b[1] - a[1]) * rad
      h = Math.sin(dlat / 2)**2 + Math.cos(a[0] * rad) * Math.cos(b[0] * rad) * Math.sin(dlng / 2)**2
      km = 2 * 6371 * Math.asin(Math.sqrt(h))
      km * ROAD_FACTOR / AVG_SPEED_KMH * 60
    end
    private_class_method :travel_minutes
  end
end
