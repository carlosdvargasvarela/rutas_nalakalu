# app/services/delivery_items/notes_updater.rb
module DeliveryItems
  class NotesUpdater
    def initialize(note_text:, current_user:, delivery_item: nil, delivery: nil, target: nil)
      @delivery_item = delivery_item
      @delivery = delivery
      @note_text = note_text
      @target = target
      @current_user = current_user
    end

    def call
      validate_note_text!

      if target == "all"
        update_all_items
      elsif delivery_item
        update_single_item
      elsif target.present?
        update_specific_item
      else
        raise ArgumentError, "Debes especificar un delivery_item o un target."
      end
    rescue => e
      Rails.logger.error("❌ Error en DeliveryItems::NotesUpdater: #{e.message}")
      raise e
    end

    private

    attr_reader :delivery_item, :delivery, :note_text, :target, :current_user

    def validate_note_text!
      raise StandardError, "La nota no puede estar vacía." if note_text.blank?
    end

    def update_single_item
      delivery_item.update!(notes: note_text)
      delivery_item
    end

    def update_all_items
      delivery.delivery_items.update_all(notes: note_text)
      delivery
    end

    def update_specific_item
      item = delivery.delivery_items.find(target)
      item.update!(notes: note_text)
      item
    end
  end
end
