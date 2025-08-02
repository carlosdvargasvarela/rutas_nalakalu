# app/models/user.rb
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Definir los roles como un enum
  enum role: { admin: 0, production_manager: 1, seller: 2, logistics: 3, driver: 4 }

  # Establecer un rol por defecto al crear un usuario
  after_initialize :set_default_role, if: :new_record?

  # Relaciones
  has_one :seller

  # Metodos
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

  private

  def set_default_role
    self.role ||= :seller # O el rol que consideres por defecto
  end
end
