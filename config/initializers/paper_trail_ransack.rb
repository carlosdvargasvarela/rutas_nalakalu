Rails.application.config.to_prepare do
  PaperTrail::Version.class_eval do
    # Filtra por "TipoModelo#ID", "TipoModelo" o "#ID"
    scope :by_resource_text, ->(text) {
      return all if text.blank?

      parts     = text.to_s.strip.split("#", 2)
      type_part = parts[0].presence
      id_part   = parts[1]&.strip.presence

      scope = all
      scope = scope.where(item_type: type_part)  if type_part.present?
      scope = scope.where(item_id: id_part.to_i) if id_part.present? && id_part.match?(/\A\d+\z/)
      scope
    }

    def self.ransackable_attributes(_auth_object = nil)
      %w[id item_type item_id event whodunnit object object_changes created_at]
    end

    def self.ransackable_associations(_auth_object = nil)
      []
    end

    def self.ransackable_scopes(_auth_object = nil)
      %i[by_resource_text]
    end
  end
end
