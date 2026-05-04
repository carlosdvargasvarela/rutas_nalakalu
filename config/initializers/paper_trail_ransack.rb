Rails.application.config.to_prepare do
  PaperTrail::Version.class_eval do
    def self.ransackable_attributes(_auth_object = nil)
      %w[
        id
        item_type
        item_id
        event
        whodunnit
        object
        object_changes
        created_at
      ]
    end

    def self.ransackable_associations(_auth_object = nil)
      []
    end

    def self.ransackable_scopes(_auth_object = nil)
      %i[by_resource_text]
    end
  end
end
