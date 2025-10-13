# app/models/crew_member.rb
class CrewMember < ApplicationRecord
  has_paper_trail

  belongs_to :user

  validates :name, presence: true
  validates :id_number, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }

  def self.ransackable_attributes(_ = nil)
    %w[name id_number created_at updated_at user_id]
  end

  def self.ransackable_associations(_ = nil)
    %w[user]
  end
end