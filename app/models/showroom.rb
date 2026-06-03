class Showroom < ApplicationRecord
  belongs_to :delivery_address, optional: true

  has_many :source_deliveries,      class_name: "Delivery", foreign_key: :source_showroom_id,      dependent: :nullify
  has_many :destination_deliveries, class_name: "Delivery", foreign_key: :destination_showroom_id, dependent: :nullify

  serialize :order_number_prefixes, coder: JSON
  serialize :order_number_keywords, coder: JSON
  serialize :inter_sala_keywords,   coder: JSON
  serialize :product_keywords,      coder: JSON

  validates :name, :code, presence: true
  validates :code, uniqueness: { case_sensitive: false }

  before_validation :upcase_code

  def address_display
    delivery_address&.address || "Sin dirección configurada"
  end

  private

  def upcase_code
    self.code = code&.upcase&.strip
  end
end
