class AddCondoFieldsToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :condominio_number, :string
    add_column :deliveries, :casa_number, :string
  end
end
