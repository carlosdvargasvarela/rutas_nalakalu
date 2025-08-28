# app/models/user.rb
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :recoverable, :rememberable, :validatable, :trackable, :lockable, :registerable

  # Definir los roles como un enum
  enum role: { admin: 0, production_manager: 1, seller: 2, logistics: 3, driver: 4 }

  attr_accessor :seller_code

  validate :seller_code_presence_if_seller

  # Establecer un rol por defecto al crear un usuario
  after_initialize :set_default_role, if: :new_record?

  # Relaciones
  has_paper_trail
  has_one :seller
  has_many :notifications, dependent: :destroy
  has_many :orders, foreign_key: :seller_id, dependent: :nullify
  has_many :delivery_plans, foreign_key: "driver_id", dependent: :destroy
  has_many :delivery_plan_assignments, through: :delivery_plans
  has_many :deliveries, through: :delivery_plan_assignments
  has_many :delivery_imports, dependent: :destroy

  # Metodos

  def unread_notifications_count
    notifications.unread.count
  end

  def display_role
    case role
    when "admin" then "Administrador"
    when "production_manager" then "Producción"
    when "seller" then "Vendedor"
    when "logistics" then "Logística"
    when "driver" then "Conductor"
    else role.to_s.humanize
    end
  end

  def seller_code_presence_if_seller
    if seller? && seller_code.blank?
      errors.add(:seller_code, "debe estar presente para vendedores")
    end
  end

  private

  def set_default_role
    self.role ||= :seller
  end

  # Ransack: permitir solo atributos seguros
  def self.ransackable_attributes(auth_object = nil)
    %w[email name role created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    [] # no exponemos asociaciones desde User para búsqueda
  end

  def self.ransackable_associations(_ = nil)
    ["orders", "user", "versions"]
  end
end
