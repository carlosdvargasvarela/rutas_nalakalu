# app/models/paper_trail/version.rb
module PaperTrail
  class Version < ::ActiveRecord::Base
    include PaperTrail::VersionConcern
    self.table_name = "versions"

    def self.ransackable_attributes(_auth_object = nil)
      %w[
        id
        item_type
        item_id
        event
        whodunnit
        object
        created_at
      ]
    end

    def self.ransackable_associations(_auth_object = nil)
      []
    end

    # Scope para buscar por texto de recurso
    scope :by_resource_text, ->(text) {
      return all if text.blank?
      
      # Si contiene #, separar tipo e ID
      if text.include?('#')
        type, id = text.split('#', 2)
        where(item_type: type.strip, item_id: id.strip)
      else
        # Solo buscar por tipo
        where("item_type LIKE ?", "%#{text}%")
      end
    }

    # Hacer el scope disponible para Ransack
    def self.ransackable_scopes(_auth_object = nil)
      [:by_resource_text]
    end
  end
end