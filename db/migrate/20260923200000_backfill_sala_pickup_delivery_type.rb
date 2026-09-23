class BackfillSalaPickupDeliveryType < ActiveRecord::Migration[7.2]
  def up
    ids = DeliveryEvent.where(action: "sala_pickup_created").filter_map { |e| JSON.parse(e.payload.to_s)["new_delivery_id"] rescue nil }
    Delivery.where(id: ids, delivery_type: :only_pickup).update_all(delivery_type: 9)
  end

  def down
    Delivery.where(delivery_type: 9).update_all(delivery_type: 5)
  end
end
