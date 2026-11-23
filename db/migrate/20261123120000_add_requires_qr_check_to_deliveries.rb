class AddRequiresQrCheckToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :requires_qr_check, :boolean, default: false, null: false
  end
end
