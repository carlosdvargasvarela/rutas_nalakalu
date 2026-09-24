module Deliveries
  # Minutos aproximados que le faltan al camión para llegar a una parada que
  # aún no inicia, SIN exponer posición ni direcciones al cliente.
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
      @plan = assignment.delivery_plan
    end

    # @return [Integer, nil] nil si no hay GPS reciente o falta alguna coordenada
    def minutes
      return unless @plan.current_lat && @plan.last_seen_at && @plan.last_seen_at > MAX_GPS_AGE.ago

      ahead = @plan.delivery_plan_assignments.where(status: %i[pending in_route])
        .where("stop_order < ?", @assignment.stop_order).order(:stop_order)
        .includes(delivery: [:delivery_address, {delivery_items: :order_item}]).to_a
      points = [[@plan.current_lat, @plan.current_lng]] +
        (ahead.map { |a| a.delivery.delivery_address } + [@assignment.delivery.delivery_address])
          .map { |addr| [addr.latitude, addr.longitude] }
      return if points.flatten.any?(&:nil?)

      total = points.each_cons(2).sum { |a, b| travel_minutes(a, b) } +
        ahead.map(&:stop_order).uniq.size * STOP_MINUTES + ahead.sum { |a| buffer_minutes(a.delivery) }
      ((total / ROUND_TO.to_f).ceil * ROUND_TO).clamp(ROUND_TO, nil)
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
    def buffer_minutes(delivery)
      rules = self.class.buffer_rules
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

    private

    def travel_minutes(a, b)
      rad = Math::PI / 180
      dlat = (b[0] - a[0]) * rad
      dlng = (b[1] - a[1]) * rad
      h = Math.sin(dlat / 2)**2 + Math.cos(a[0] * rad) * Math.cos(b[0] * rad) * Math.sin(dlng / 2)**2
      km = 2 * 6371 * Math.asin(Math.sqrt(h))
      km * ROAD_FACTOR / AVG_SPEED_KMH * 60
    end
  end
end
