# app/models/paper_trail/version.rb
module PaperTrail
  class Version < ::ActiveRecord::Base
    include PaperTrail::VersionConcern
    self.table_name = "versions"

    # IMPORTANTE: Lista explícita de atributos que Ransack puede usar
    def self.ransackable_attributes(_auth_object = nil)
      %w[
        id
        item_type
        item_id
        event
        whodunnit
        object
        created_at
        # object_changes # descomenta si tu versions table lo tiene y querés permitirlo
      ]
    end

    # Opcional: si quisieras permitir búsquedas por asociaciones (no aplican aquí)
    def self.ransackable_associations(_auth_object = nil)
      []
    end
  end
end
