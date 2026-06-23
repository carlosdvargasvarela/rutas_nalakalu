module DeliveryItems
  class CancelToShowroomCreator
    def initialize(delivery_item:, showroom:, delivery_date:, current_user:, notes: nil)
      @delivery_item = delivery_item
      @showroom      = showroom
      @delivery_date = delivery_date
      @current_user  = current_user
      @notes         = notes
    end

    def call
      raise ArgumentError, "La sala '#{@showroom.name}' no tiene dirección configurada." unless @showroom.delivery_address.present?
      raise ArgumentError, "Debe seleccionar una fecha de entrega a sala." if @delivery_date.blank?

      PaperTrail.request(whodunnit: @current_user.id.to_s) do
        ActiveRecord::Base.transaction do
          DeliveryItems::StatusUpdater.new(
            delivery_item: @delivery_item,
            new_status:    :cancelled,
            current_user:  @current_user
          ).call

          client     = find_or_create_showroom_client
          seller     = find_or_create_showroom_seller(client)
          order      = create_order(client, seller)
          order_item = create_order_item(order)
          delivery   = create_delivery(order)

          DeliveryItem.create!(
            delivery:           delivery,
            order_item:         order_item,
            quantity_delivered: @delivery_item.quantity_delivered,
            status:             :confirmed
          )

          DeliveryEvent.record(
            delivery: @delivery_item.delivery,
            action:   "cancelled_to_showroom",
            actor:    @current_user,
            payload:  {
              showroom:        @showroom.name,
              new_delivery_id: delivery.id,
              product:         @delivery_item.product
            }
          )

          delivery
        end
      end
    end

    private

    def find_or_create_showroom_client
      Client.find_or_create_by!(name: "NaLakalu Showrooms") do |c|
        c.email = "showrooms@nalakalu.com"
        c.phone = "0000-0000"
      end
    end

    def find_or_create_showroom_seller(client)
      Seller.find_or_create_by!(seller_code: "NALAKALU_SHOW") do |s|
        s.user = @current_user
        s.name = "Movimientos Showroom"
      end
    end

    def create_order(client, seller)
      client.orders.create!(
        number: "RESTOCK_#{@showroom.code}",
        seller: seller,
        status: :ready_for_delivery
      )
    end

    def create_order_item(order)
      orig = @delivery_item.order_item
      order.order_items.create!(
        product:  orig.product,
        quantity: @delivery_item.quantity_delivered,
        status:   :ready
      )
    end

    def create_delivery(order)
      original = @delivery_item.delivery
      Delivery.create!(
        order:                order,
        delivery_address:     @showroom.delivery_address,
        delivery_date:        @delivery_date,
        delivery_type:        :showroom,
        status:               :scheduled,
        destination_showroom: @showroom,
        contact_name:         "Encargado de Sala",
        delivery_notes:       build_notes(original)
      )
    end

    def build_notes(original)
      cancelacion = Deliveries::Vocabulary.service_type_label("cancelacion")
      base = "#{cancelacion} de producción — #{@delivery_item.product} " \
             "(pedido ##{original.order_number}, entrega: #{original.delivery_date.strftime("%d/%m/%Y")})."
      @notes.present? ? "#{base} #{@notes}" : base
    end
  end
end
