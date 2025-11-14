# app/services/delivery_plan_stop_grouper.rb
class DeliveryPlanStopGrouper
  SAME_LOCATION_THRESHOLD_METERS = 50

  def initialize(delivery_plan)
    @delivery_plan = delivery_plan
  end

  def call
    assignments = @delivery_plan.delivery_plan_assignments
                    .includes(delivery: :delivery_address)
                    .order(:stop_order)

    return if assignments.empty?

    location_groups = group_by_location(assignments)
    assign_stop_numbers(location_groups)
  end

  def find_stop_for_location(delivery)
    target_loc = extract_location(delivery)
    return nil if target_loc.nil?

    @delivery_plan.delivery_plan_assignments
                 .includes(delivery: :delivery_address)
                 .each do |assignment|
      existing_loc = extract_location(assignment.delivery)
      next if existing_loc.nil?

      return assignment.stop_order if same_location?(target_loc, existing_loc)
    end

    nil
  end

  private

  def group_by_location(assignments)
    groups = []
    processed = Set.new

    assignments.each do |assignment|
      next if processed.include?(assignment.id)

      loc = extract_location(assignment.delivery)

      if loc.nil?
        groups << [ assignment ]
        processed.add(assignment.id)
        next
      end

      group = [ assignment ]
      processed.add(assignment.id)

      assignments.each do |other|
        next if processed.include?(other.id)

        other_loc = extract_location(other.delivery)
        next if other_loc.nil?

        if same_location?(loc, other_loc)
          group << other
          processed.add(other.id)
        end
      end

      groups << group
    end

    groups
  end

  def assign_stop_numbers(location_groups)
    stop_number = 1

    location_groups.each do |group|
      group.each do |assignment|
        assignment.update_column(:stop_order, stop_number)
      end
      stop_number += 1
    end
  end

  def extract_location(delivery)
    addr = delivery.delivery_address
    return nil if addr.nil?

    lat = addr.latitude
    lng = addr.longitude

    return nil if lat.blank? || lng.blank?

    { lat: lat.to_f, lng: lng.to_f }
  end

  def same_location?(loc1, loc2)
    haversine_distance(loc1[:lat], loc1[:lng], loc2[:lat], loc2[:lng]) <= SAME_LOCATION_THRESHOLD_METERS
  end

  def haversine_distance(lat1, lon1, lat2, lon2)
    rad = Math::PI / 180
    rkm = 6371
    rm = rkm * 1000

    dlat = (lat2 - lat1) * rad
    dlon = (lon2 - lon1) * rad

    lat1_rad = lat1 * rad
    lat2_rad = lat2 * rad

    a = Math.sin(dlat / 2)**2 +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon / 2)**2

    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    rm * c
  end
end
