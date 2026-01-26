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

    def error_summary
      errors.group_by { |e| e[:category] }.transform_values(&:count)
    end

    private

    def detect_all_errors
      detected = []

      # 1. Errores de dirección
      detected.concat(address_errors)

      # 2. Errores de contacto
      detected.concat(contact_errors)

      # 3. Errores de productos
      detected.concat(product_errors)

      # 4. Errores de fecha
      detected.concat(date_errors)

      # 5. Errores de cliente
      detected.concat(client_errors)

      # 6. Errores de orden
      detected.concat(order_errors)

      detected
    end

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

      # Dirección vacía o muy corta
      if address.address.blank?
        errors << {
          category: "Dirección",
          severity: "critical",
          message: "Dirección vacía"
        }
      elsif address.address.length < 10
        errors << {
          category: "Dirección",
          severity: "warning",
          message: "Dirección muy corta (menos de 10 caracteres)"
        }
      end

      # Sin coordenadas
      if address.latitude.blank? || address.longitude.blank?
        errors << {
          category: "Dirección",
          severity: "high",
          message: "Sin coordenadas GPS (no se puede ubicar en el mapa)"
        }
      end

      # Coordenadas fuera de Costa Rica
      if address.latitude.present? && address.longitude.present?
        unless address.in_costa_rica?
          errors << {
            category: "Dirección",
            severity: "high",
            message: "Coordenadas fuera de Costa Rica"
          }
        end
      end

      # Provincia/cantón/distrito vacíos
      if address.province.blank?
        errors << {
          category: "Dirección",
          severity: "medium",
          message: "Sin provincia especificada"
        }
      end

      if address.canton.blank?
        errors << {
          category: "Dirección",
          severity: "medium",
          message: "Sin cantón especificado"
        }
      end

      if address.district.blank?
        errors << {
          category: "Dirección",
          severity: "low",
          message: "Sin distrito especificado"
        }
      end

      errors
    end

    def contact_errors
      errors = []

      # Sin nombre de contacto
      if delivery.contact_name.blank?
        errors << {
          category: "Contacto",
          severity: "high",
          message: "Sin nombre de contacto"
        }
      end

      # Sin teléfono
      if delivery.contact_phone.blank?
        errors << {
          category: "Contacto",
          severity: "critical",
          message: "Sin teléfono de contacto"
        }
      elsif !valid_phone_format?(delivery.contact_phone)
        errors << {
          category: "Contacto",
          severity: "medium",
          message: "Formato de teléfono inválido: #{delivery.contact_phone}"
        }
      end

      errors
    end

    def product_errors
      errors = []

      # Sin productos
      if delivery.delivery_items.empty?
        errors << {
          category: "Productos",
          severity: "critical",
          message: "Entrega sin productos"
        }
        return errors
      end

      # Items con cantidad cero o negativa
      delivery.delivery_items.each do |item|
        if item.quantity_delivered.to_i <= 0
          errors << {
            category: "Productos",
            severity: "high",
            message: "Producto '#{item.order_item.product}' con cantidad inválida (#{item.quantity_delivered})"
          }
        end
      end

      # Items con estado problemático
      problematic_items = delivery.delivery_items.select do |item|
        item.status.in?(%w[cancelled failed])
      end

      if problematic_items.any?
        errors << {
          category: "Productos",
          severity: "medium",
          message: "#{problematic_items.count} producto(s) con estado problemático"
        }
      end

      # Items sin producto especificado
      delivery.delivery_items.each do |item|
        if item.order_item.product.blank?
          errors << {
            category: "Productos",
            severity: "high",
            message: "Item sin descripción de producto"
          }
        end
      end

      errors
    end

    def date_errors
      errors = []

      # Sin fecha de entrega
      if delivery.delivery_date.blank?
        errors << {
          category: "Fecha",
          severity: "critical",
          message: "Sin fecha de entrega programada"
        }
        return errors
      end

      # Fecha en el pasado
      if delivery.delivery_date < Date.today
        errors << {
          category: "Fecha",
          severity: "high",
          message: "Fecha de entrega en el pasado (#{I18n.l(delivery.delivery_date)})"
        }
      end

      # Fecha muy lejana (más de 60 días)
      if delivery.delivery_date > Date.today + 60.days
        errors << {
          category: "Fecha",
          severity: "warning",
          message: "Fecha de entrega muy lejana (#{I18n.l(delivery.delivery_date)})"
        }
      end

      errors
    end

    def client_errors
      errors = []
      client = delivery.order.client

      # Cliente sin email
      if client.email.blank?
        errors << {
          category: "Cliente",
          severity: "low",
          message: "Cliente sin email configurado"
        }
      end

      # Cliente sin teléfono
      if client.phone.blank?
        errors << {
          category: "Cliente",
          severity: "medium",
          message: "Cliente sin teléfono configurado"
        }
      end

      errors
    end

    def order_errors
      errors = []
      order = delivery.order

      # Orden sin número
      if order.number.blank?
        errors << {
          category: "Orden",
          severity: "high",
          message: "Orden sin número asignado"
        }
      end

      # Orden sin vendedor
      if order.seller.blank?
        errors << {
          category: "Orden",
          severity: "critical",
          message: "Orden sin vendedor asignado"
        }
      end

      # Orden sin items
      if order.order_items.empty?
        errors << {
          category: "Orden",
          severity: "critical",
          message: "Orden sin productos"
        }
      end

      errors
    end

    def valid_phone_format?(phone)
      # Formato básico para Costa Rica: 8 dígitos, puede tener guiones o espacios
      cleaned = phone.to_s.gsub(/[\s\-()]/, "")
      cleaned.match?(/^\d{8}$/)
    end
  end
end
