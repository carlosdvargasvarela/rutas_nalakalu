# app/models/client.rb
class Client < ApplicationRecord
  has_paper_trail
  has_many :delivery_addresses, dependent: :destroy
  # Los pedidos en stand-by de QuickBooks no se usan hasta liberarlos (ver Admin::QuickbooksController#release).
  has_many :orders, -> { where(qb_standby: false) }, dependent: :destroy
  has_many :standby_orders, -> { where(qb_standby: true) }, class_name: "Order", dependent: :destroy
  has_many :client_notes, dependent: :destroy  # <- AGREGAR

  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["name", "phone", "email", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["delivery_addresses", "orders", "versions"]
  end

  # Helpers para el panel
  def pinned_notes
    client_notes.pinned.order(created_at: :desc)
  end

  def notes_count
    client_notes.count
  end
end
