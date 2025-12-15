# app/services/deliveries/updater.rb
module Deliveries
  class Updater
    def initialize(delivery:, params:, current_user:)
      @delivery = delivery
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        @order = find_or_resolve_order
        @client = @order.client
        @address = find_or_create_address(@client)

        prevent_duplicates!

        @delivery.delivery_address = @address
        update_delivery_items if delivery_params[:delivery_items_attributes].present?

        @delivery.update!(delivery_params.except(:delivery_items_attributes, :delivery_address_id, :order_id))
      end

      @delivery
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("❌ Error en Deliveries::Updater: #{e.message}")
      raise e
    rescue ActiveRecord::RecordNotUnique
      raise StandardError, "Ya existe otra entrega con esa combinación de pedido, fecha y dirección."
    end

    private

    attr_reader :delivery, :params, :current_user

    def delivery_params
      params.require(:delivery).permit(
        :delivery_date,
        :delivery_address_id,
        :order_id,
        :contact_name,
        :contact_phone,
        :delivery_notes,
        :delivery_type,
        :delivery_time_preference,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :service_case, :status, :notes, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
    end

    def normalize_id(raw)
      s = raw.to_s.strip
      return nil if s.blank? || s == "__new__"
      s
    end

    def find_or_resolve_order
      order_id = normalize_id(delivery_params[:order_id])
      return Order.find(order_id) if order_id.present?
      delivery.order
    end

    def find_or_create_address(client)
      addr_id = normalize_id(delivery_params[:delivery_address_id])

      if addr_id.present?
        addr = DeliveryAddress.find(addr_id)

        # Si vienen nuevos datos de dirección, actualizarlos
        if params[:delivery_address].present? && address_params.values.any?(&:present?)
          # Priorizar coordenadas si vienen
          update_attrs = address_params.dup

          lat = update_attrs[:latitude].to_s.strip
          lng = update_attrs[:longitude].to_s.strip

          # Si hay coordenadas, asegurarse de que se actualicen primero
          if lat.present? && lng.present?
            addr.latitude = lat.to_f
            addr.longitude = lng.to_f
          end

          # Actualizar el resto de atributos
          addr.assign_attributes(update_attrs.except(:latitude, :longitude))
          addr.save!
        end

        addr
      elsif params[:delivery_address]&.[](:address).present?
        addr_attrs = address_params
        address_text = addr_attrs[:address].to_s.strip

        lat = addr_attrs[:latitude].to_s.strip
        lng = addr_attrs[:longitude].to_s.strip

        # Buscar por coordenadas primero si están presentes
        if lat.present? && lng.present?
          existing = client.delivery_addresses.find_by(
            latitude: lat.to_f.round(6),
            longitude: lng.to_f.round(6)
          )
          return existing if existing
        end

        # Buscar por dirección
        existing = client.delivery_addresses.find_by(address: address_text)
        if existing
          # Actualizar coordenadas si vienen nuevas
          if lat.present? && lng.present?
            existing.update!(latitude: lat.to_f, longitude: lng.to_f)
          end
          return existing
        end

        # Crear nueva
        client.delivery_addresses.create!(addr_attrs)
      else
        raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debes seleccionar o ingresar una dirección."
      end
    end

    def address_params
      params.require(:delivery_address).permit(:address, :description, :latitude, :longitude, :plus_code)
    end

    def prevent_duplicates!
      new_date = delivery_params[:delivery_date]
      return unless new_date != delivery.delivery_date || @address != delivery.delivery_address

      existing_delivery = Delivery.find_by(
        order: @order,
        delivery_date: new_date,
        delivery_address: @address
      )

      if existing_delivery && existing_delivery != delivery
        raise ActiveRecord::RecordNotUnique
      end
    end

    def update_delivery_items
      processed_items = process_delivery_items_params(@order)
      delivery.delivery_items = processed_items
    end

    def process_delivery_items_params(order)
      delivery_params[:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"

        if item_params[:id].present?
          update_existing_delivery_item(item_params)
        else
          build_new_delivery_item(order, item_params)
        end
      end.compact
    end

    def update_existing_delivery_item(item_params)
      di = DeliveryItem.find(item_params[:id])
      di.update!(
        quantity_delivered: item_params[:quantity_delivered] || di.quantity_delivered,
        service_case: item_params[:service_case] == "1",
        status: item_params[:status] || di.status,
        notes: item_params[:notes] || di.notes
      )

      update_order_item_if_needed(item_params[:order_item_attributes])
      di
    end

    def update_order_item_if_needed(oi_params)
      return unless oi_params.present? && oi_params[:id].present?

      order_item = OrderItem.find(oi_params[:id])
      permitted_update = {
        product: oi_params[:product] || order_item.product,
        quantity: oi_params[:quantity] || order_item.quantity,
        notes: oi_params[:notes] || order_item.notes
      }
      order_item.update!(permitted_update)
    end

    def build_new_delivery_item(order, item_params)
      return if item_params[:order_item_attributes].blank? || item_params[:order_item_attributes][:product].blank?

      order_item = find_or_create_order_item(order, item_params[:order_item_attributes])

      DeliveryItem.new(
        order_item: order_item,
        quantity_delivered: (item_params[:quantity_delivered].presence || 1).to_i,
        service_case: item_params[:service_case] == "1",
        status: :pending,
        notes: item_params[:notes]
      )
    end

    def find_or_create_order_item(order, oi_params)
      if oi_params[:id].present?
        order_item = OrderItem.find(oi_params[:id])
        order_item.update!(
          product: oi_params[:product] || order_item.product,
          quantity: oi_params[:quantity] || order_item.quantity,
          notes: oi_params[:notes] || order_item.notes
        )
        return order_item
      end

      existing_item = order.order_items.find_by(product: oi_params[:product])
      if existing_item
        existing_item.update!(
          quantity: oi_params[:quantity] || existing_item.quantity,
          notes: [existing_item.notes, oi_params[:notes]].compact.reject(&:blank?).join("; ")
        )
        existing_item
      else
        order.order_items.create!(
          product: oi_params[:product],
          quantity: (oi_params[:quantity].presence || 1).to_i,
          notes: oi_params[:notes],
          status: :in_production
        )
      end
    end
  end
end
