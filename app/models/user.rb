# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one :seller, dependent: :destroy

  enum role: {
    admin: 0,
    production_manager: 1,
    seller: 1,
    logistics: 2,
    driver: 3
  }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  def display_role
    role.humanize
  end
end

