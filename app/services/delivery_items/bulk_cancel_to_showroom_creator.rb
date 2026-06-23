module DeliveryItems
  class BulkCancelToShowroomCreator
    def initialize(delivery:, items:, showroom:, delivery_date:, current_user:, notes: nil)
      @delivery      = delivery
      @items         = items
      @showroom      = showroom
      @delivery_date = delivery_date
      @current_user  = current_user
      @notes         = notes
    end

    def call
      raise ArgumentError, "La sala '#{@showroom.name}' no tiene dirección configurada." unless @showroom.delivery_address.present?
      raise ArgumentError, "Debe seleccionar una fecha de entrega a sala." if @delivery_date.blank?
      raise ArgumentError, "No hay productos cancelables seleccionados." if @items.empty?

      PaperTrail.request(whodunnit: @current_user.id.to_s) do
        ActiveRecord::Base.transaction do
          @items.each do |item|
            DeliveryItems::StatusUpdater.new(
              delivery_item: item,
              new_status:    :cancelled,
              current_user:  @current_user
            ).call
          end

          client           = find_or_create_showroom_client
          seller           = find_or_create_showroom_seller(client)
          order            = create_order(client, seller)
          showroom_delivery = create_delivery(order)

          @items.each do |item|
            order_item = order.order_items.create!(
              product:  item.order_item.product,
              quantity: item.quantity_delivered,
              status:   :ready
            )
            DeliveryItem.create!(
              delivery:           showroom_delivery,
              order_item:         order_item,
              quantity_delivered: item.quantity_delivered,
              status:             :confirmed
            )
          end

          DeliveryEvent.record(
            delivery: @delivery,
            action:   "bulk_cancelled_to_showroom",
            actor:    @current_user,
            payload:  {
              showroom:        @showroom.name,
              new_delivery_id: showroom_delivery.id,
              items_count:     @items.count
            }
          )

          showroom_delivery
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

    def create_delivery(order)
      Delivery.create!(
        order:                order,
        delivery_address:     @showroom.delivery_address,
        delivery_date:        @delivery_date,
        delivery_type:        :showroom,
        status:               :scheduled,
        destination_showroom: @showroom,
        contact_name:         "Encargado de Sala",
        delivery_notes:       build_notes
      )
    end

    def build_notes
      cancelacion = Deliveries::Vocabulary.service_type_label("cancelacion")
      base = "Restock por #{cancelacion.downcase} — Pedido ##{@delivery.order_number} " \
             "(entrega: #{@delivery.delivery_date.strftime("%d/%m/%Y")}). #{@items.count} producto(s)."
      @notes.present? ? "#{base} #{@notes}" : base
    end
  end
end
