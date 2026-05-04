module PaperTrail
  class Version < ::ActiveRecord::Base
    include PaperTrail::VersionConcern

    self.table_name = "versions"

    scope :by_resource_text, ->(text) {
      return all if text.blank?

      if text.include?("#")
        type, id = text.split("#", 2)
        where(item_type: type.strip, item_id: id.strip)
      else
        where("item_type LIKE ?", "%#{text}%")
      end
    }

    def self.ransackable_scopes(_auth_object = nil)
      [:by_resource_text]
    end
  end
end
