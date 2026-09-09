# app/models/concerns/has_primary_contact.rb
# Compartido por VendorContact y OrderContact: nombre requerido, orden con
# el contacto principal primero, y al marcar uno como principal se
# desmarcan los demás del mismo dueño (pedido, proveedor, etc.).
#
# Asume que el modelo que lo incluye tiene un único belongs_to hacia su
# dueño, y que ese dueño expone la colección con el nombre plural
# convencional de Rails (Order#order_contacts, Vendor#vendor_contacts...).
module HasPrimaryContact
  extend ActiveSupport::Concern

  included do
    validates :name, presence: true

    scope :primary_first, -> { order(is_primary: :desc, created_at: :asc) }

    before_save :ensure_single_primary
  end

  private

  def ensure_single_primary
    return unless is_primary?

    owner_name = self.class.reflect_on_all_associations(:belongs_to).first.name
    owner = public_send(owner_name)
    siblings = owner.public_send(self.class.name.underscore.pluralize)
    siblings.where.not(id: id).update_all(is_primary: false)
  end
end
