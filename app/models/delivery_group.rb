class DeliveryGroup < ApplicationRecord
  has_many :delivery_group_memberships, dependent: :destroy
  has_many :deliveries, through: :delivery_group_memberships

  PROPAGATABLE_FIELDS = {
    "contact_name"             => "Nombre de contacto",
    "contact_phone"            => "Teléfono de contacto",
    "condominio_number"        => "N° Condominio",
    "casa_number"              => "N° Casa",
    "delivery_notes"           => "Notas",
    "delivery_time_preference" => "Preferencia horaria"
  }.freeze
end
