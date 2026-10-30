module DeliveryItems
  # Corrige de una vez los productos de una entrega: renombra, cambia cantidades,
  # archiva y agrega. Todo o nada, y cada cambio llega al OrderItem del pedido.
  # Deja el pedido marcado para que QuickBooks no revierta la corrección.
  class ProductsEditor
    def initialize(delivery:, items:, new_items:, current_user:)
      @delivery = delivery
      @items = items
      @new_items = new_items.reject { |attrs| attrs[:product].to_s.strip.blank? }
      @current_user = current_user
    end

    # @return [Integer] cantidad de cambios aplicados
    def call
      raise StandardError, "Esta entrega no permite cambiar productos en su estado actual." if delivery.bulk_locked?

      changes = 0
      new_item_status = delivery.default_item_status

      ActiveRecord::Base.transaction do
        # Primero archivar y después renombrar/agregar: así un producto nuevo
        # puede reutilizar el nombre del que se está reemplazando.
        to_archive, to_edit = items.partition { |_id, attrs| attrs[:archive] == "1" }
        to_archive.each do |id, _attrs|
          archive(editable_item(id))
          changes += 1
        end
        to_edit.each { |id, attrs| changes += 1 if edit(editable_item(id), attrs) }
        new_items.each do |attrs|
          add(attrs, new_item_status)
          changes += 1
        end

        if delivery.delivery_items.reload.not_archived.none?
          raise StandardError, "La entrega debe conservar al menos un producto. Si ya no aplica, archivá la entrega."
        end
        delivery.order.touch(:products_edited_at) if changes.positive?
      end

      delivery.recalculate_load_status!
      changes
    end

    private

    attr_reader :delivery, :items, :new_items, :current_user

    def editable_item(id)
      delivery.delivery_items.bulk_actionable.find(id)
    end

    def archive(item)
      unless DeliveryItemPolicy.new(current_user, item).archive?
        raise StandardError, "Solo un administrador puede archivar productos."
      end

      StatusUpdater.new(delivery_item: item, new_status: :archived, current_user: current_user).call
    end

    # @return [Boolean] true si hubo algo que cambiar
    def edit(item, attrs)
      order_item = item.order_item
      previous = {product: order_item.product, quantity: item.quantity_delivered}
      product = attrs[:product].to_s.strip
      quantity = parse_quantity(attrs[:quantity], product)
      return false if previous == {product: product, quantity: quantity}

      apply(item, product, quantity)
      record("item_edited", item, previous_product: previous[:product], previous_quantity: previous[:quantity])
      true
    end

    def add(attrs, status)
      product = attrs[:product].to_s.strip
      quantity = parse_quantity(attrs[:quantity], product)
      order_item = delivery.order.order_items.find_by(product: product)
      item = order_item && delivery.delivery_items.find_by(order_item: order_item)

      if item
        raise StandardError, "«#{product}» ya está en esta entrega." unless item.archived?

        StatusUpdater.new(delivery_item: item, new_status: :unarchived, current_user: current_user).call
        apply(item, product, quantity)
        item.update!(status: status)
      elsif order_item
        order_item.update!(quantity: order_item.quantity + quantity)
        item = delivery.delivery_items.create!(order_item: order_item, quantity_delivered: quantity, status: status)
      else
        order_item = delivery.order.order_items.create!(product: product, quantity: quantity, status: :in_production)
        item = delivery.delivery_items.create!(order_item: order_item, quantity_delivered: quantity, status: status)
      end

      record("item_added", item)
    end

    # La cantidad del pedido se mueve por diferencia: el producto puede estar
    # repartido entre varias entregas y solo cambia la parte de esta.
    def apply(item, product, quantity)
      order_item = item.order_item
      order_quantity = order_item.quantity + quantity - item.quantity_delivered.to_i
      order_item.update!(product: product, quantity: [order_quantity, quantity].max)
      item.update!(quantity_delivered: quantity)
    end

    def parse_quantity(raw, product)
      quantity = Integer(raw.to_s, 10, exception: false).to_i
      raise StandardError, "La cantidad de «#{product}» debe ser mayor a 0." unless quantity.positive?

      quantity
    end

    def record(action, item, **extra)
      DeliveryEvent.record(
        delivery: delivery,
        action: action,
        actor: current_user,
        payload: {delivery_item_id: item.id, product: item.order_item.product, quantity: item.quantity_delivered, **extra}
      )
    end
  end
end
