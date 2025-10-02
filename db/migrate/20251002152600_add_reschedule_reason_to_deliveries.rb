class AddRescheduleReasonToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :reschedule_reason, :text
  end
end
