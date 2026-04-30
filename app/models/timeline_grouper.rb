# app/models/timeline_grouper.rb
class TimelineGrouper
  GROUP_WINDOW = 60.seconds

  def self.group(entries)
    return [] if entries.blank?

    sorted = entries.sort_by(&:timestamp).reverse
    groups = []
    current = []

    sorted.each do |entry|
      if current.empty?
        current << entry
      else
        last = current.first
        same_actor = actor_id(last) == actor_id(entry)
        within_window = (last.timestamp - entry.timestamp).abs <= GROUP_WINDOW

        if same_actor && within_window
          current << entry
        else
          groups << finalize(current)
          current = [entry]
        end
      end
    end

    groups << finalize(current) unless current.empty?
    groups
  end

  # ── privado ────────────────────────────────────────────────────────────────

  def self.actor_id(entry)
    entry.delivery_event? ? entry.record.actor_id.to_s : entry.record.whodunnit.to_s
  end
  private_class_method :actor_id

  # Dentro de cada grupo, el DeliveryEvent va primero (es el "primario")
  def self.finalize(entries)
    primary = entries.find(&:delivery_event?) || entries.first
    rest = entries - [primary]
    {primary: primary, secondary: rest}
  end
  private_class_method :finalize
end
