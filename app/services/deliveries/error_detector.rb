# app/services/deliveries/error_detector.rb
module Deliveries
  class ErrorDetector
    attr_reader :delivery

    def initialize(delivery)
      @delivery = delivery
    end

    def has_errors?
      errors.any?
    end

    def errors
      @errors ||= detect_all_errors
    end

    # Devuelve un hash { "Dirección" => 3, "Contacto" => 1, ... }
    def error_summary
      errors.group_by { |e| e[:category] }.transform_values(&:count)
    end

    private

    def detect_all_errors
      detected = []

      detected.concat(address_errors)
      detected.concat(contact_errors)
      detected.concat(product_errors)
      detected.concat(date_errors)
      detected.concat(client_errors)
      detected.concat(order_errors)

      detected
    end

    # ==========================
    # 1. ERRORES DE DIRECCIÓN
    # ==========================
    def address_errors
      errors = []
      address = delivery.delivery_address

      if address.blank?
        errors << {
          category: "Dirección",
          severity: "critical",
          message: "Sin dirección de entrega configurada"
        }
        return errors
      end

      # Usamos la lógica centralizada del modelo DeliveryAddress. Cada
      # chequeo ya declara su propia severidad ahí mismo — nada de adivinarla
      # con regex sobre el texto del mensaje.
      address.address_errors_with_severity.each do |finding|
        errors << {
          category: "Dirección",
          severity: finding[:severity],
          message: finding[:message]
        }
      end

      errors
    end

    # ==========================
    # 2. ERRORES DE CONTACTO
    # ==========================
    # Un pedido con contactos propios (order_contacts) ya no depende de los
    # campos contact_name/contact_phone de la entrega — esos solo son el
    # fallback legacy para pedidos que nunca migraron a contactos múltiples
    # (ver app/views/deliveries/_order_contacts_display.html.erb, la misma
    # prioridad se usa ahí para mostrarlos).
    def contact_errors
      errors = []
      order_contacts = delivery.order&.order_contacts.presence

      if order_contacts.present?
        if order_contacts.none? { |c| c.phone.present? }
          errors << {
            category: "Contacto",
            severity: "critical",
            message: "Ningún contacto del pedido tiene teléfono registrado"
          }
        end
      else
        if delivery.contact_name.blank?
          errors << {
            category: "Contacto",
            severity: "high",
            message: "Sin nombre de contacto"
          }
        end

        if delivery.contact_phone.blank?
          errors << {
            category: "Contacto",
            severity: "critical",
            message: "Sin teléfono de contacto"
          }
        end
      end

      errors
    end

    # ==========================
    # 3. ERRORES DE PRODUCTOS
    # ==========================
    def product_errors
      errors = []

      if delivery.delivery_items.empty?
        errors << {
          category: "Productos",
          severity: "critical",
          message: "Entrega sin productos"
        }
        return errors
      end

      delivery.delivery_items.each do |item|
        # Cantidad inválida
        if item.quantity_delivered.to_i <= 0
          errors << {
            category: "Productos",
            severity: "high",
            message: "Producto '#{item.order_item.product}' con cantidad inválida (#{item.quantity_delivered})"
          }
        end

        # Sin descripción de producto
        if item.order_item.product.blank?
          errors << {
            category: "Productos",
            severity: "high",
            message: "Producto sin descripción configurada (item ##{item.id} del pedido)"
          }
        end

        # Entregado más de lo pedido
        if item.quantity_delivered.to_i > item.order_item.quantity.to_i
          errors << {
            category: "Productos",
            severity: "high",
            message: "Producto '#{item.order_item.product}': se entregó #{item.quantity_delivered} pero se pidieron #{item.order_item.quantity}"
          }
        end
      end

      # Items con estado problemático: uno por producto, para saber cuál y por qué.
      delivery.delivery_items.select { |item| item.status.in?(%w[cancelled failed]) }.each do |item|
        errors << {
          category: "Productos",
          severity: "medium",
          message: "Producto '#{item.order_item.product}' en estado #{item.status.humanize.downcase}"
        }
      end

      errors
    end

    # ==========================
    # 4. ERRORES DE FECHA
    # ==========================
    def date_errors
      errors = []

      if delivery.delivery_date.blank?
        errors << {
          category: "Fecha",
          severity: "critical",
          message: "Sin fecha de entrega programada"
        }
        return errors
      end

      if delivery.delivery_date < Date.current
        errors << {
          category: "Fecha",
          severity: "high",
          message: "Fecha de entrega en el pasado (#{I18n.l(delivery.delivery_date)})"
        }
      end

      errors
    end

    # ==========================
    # 5. ERRORES DE CLIENTE
    # ==========================
    def client_errors
      errors = []
      client = delivery.order&.client

      return errors if client.blank?

      errors
    end

    # ==========================
    # 6. ERRORES DE ORDEN
    # ==========================
    def order_errors
      errors = []
      order = delivery.order

      if order.blank?
        return [{
          category: "Orden",
          severity: "critical",
          message: "Entrega sin orden asociada"
        }]
      end

      if order.number.blank?
        errors << {
          category: "Orden",
          severity: "high",
          message: "Orden sin número asignado"
        }
      end

      if order.seller.blank?
        errors << {
          category: "Orden",
          severity: "critical",
          message: "Orden sin vendedor asignado"
        }
      end

      if order.order_items.empty?
        errors << {
          category: "Orden",
          severity: "critical",
          message: "Orden sin productos"
        }
      end

      errors
    end
  end
end
