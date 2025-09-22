# app/controllers/deliveries_controller.rb
class DeliveriesController < ApplicationController
  before_action :set_delivery, only: [ :show, :edit, :update, :mark_as_delivered, :confirm_all_items, :reschedule_all ]
  before_action :set_addresses, only: [ :new, :edit, :create, :update ]

  # GET /deliveries
  # Muestra todas las entregas o filtra por semana
  def index
    session[:deliveries_return_to] = request.fullpath

    # Aplicar filtro de rescheduled antes de Ransack para evitar conflictos SQL
    base_scope = Delivery.all
    unless params[:show_rescheduled] == "1"
      base_scope = base_scope.where.not(status: :rescheduled)
    end

    @q = base_scope.ransack(params[:q])
    deliveries_scope = @q.result.includes(order: [ :client, :seller ], delivery_address: :client)

    # HTML con paginación
    @deliveries = deliveries_scope.order(delivery_date: :asc).page(params[:page])

    # Excel/CSV sin paginación
    @all_deliveries = deliveries_scope.includes(delivery_items: { order_item: :order }).order(delivery_date: :asc)

    authorize Delivery

    respond_to do |format|
      format.html
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=entregas_#{Date.today.strftime('%Y%m%d')}.xlsx"
      }
      format.csv {
        send_data @all_deliveries.to_csv, filename: "entregas_#{Date.today.strftime('%Y%m%d')}.csv"
      }
    end
  end

  # GET /deliveries/:id
  # Muestra los detalles de una entrega específica
  def show
    @future_deliveries = Delivery
      .where(order_id: @delivery.order_id, delivery_address_id: @delivery.delivery_address_id)
      .where.not(id: @delivery.id, status: :rescheduled)

    @delivery_history = @delivery.delivery_history
  end

  # GET /deliveries/new
  def new
    if params[:order_id].present?
      @order = Order.find(params[:order_id])
      @client = @order.client
      @delivery = @order.deliveries.build
      @delivery.build_delivery_address(client: @client)
    else
      @order = Order.new
      @client = Client.new
      @delivery = Delivery.new
      @delivery.build_delivery_address
    end

    # Construir un delivery_item vacío con order_item anidado para el formulario
    @delivery.delivery_items.build.build_order_item

    @clients = Client.all.order(:name)
    @addresses = (@client&.delivery_addresses || []).to_a
  end

  # GET /deliveries/:id/edit
  def edit
    @delivery = Delivery.includes(delivery_items: :order_item).find(params[:id])
    @client = @delivery.order.client
    @order = @delivery.order

    # Agregar un delivery_item vacío si no hay ninguno
    @delivery.delivery_items.build.build_order_item if @delivery.delivery_items.empty?
  end

  # PATCH/PUT /deliveries/:id
  def update
    ActiveRecord::Base.transaction do
      # 1. Si el usuario cambió el pedido, busca el nuevo order
      order = if params[:delivery][:order_id].present?
        Order.find(params[:delivery][:order_id])
      else
        @delivery.order
      end

      client = order.client
      address = find_or_create_address(client)
      @delivery.delivery_address = address

      # 2. Procesa los delivery_items (existentes y nuevos)
      if params[:delivery][:delivery_items_attributes].present?
        processed_delivery_items = process_delivery_items_params(order)
        @delivery.delivery_items = processed_delivery_items
      end

      # 3. Actualiza la entrega
      if @delivery.update(delivery_params.except(:delivery_items_attributes, :delivery_address_id))
        redirect_to(session.delete(:deliveries_return_to) || deliveries_path,
                    notice: "Entrega actualizada correctamente.")
      else
        @client = order.client
        @addresses = @client.delivery_addresses.order(:description)
        @order = order
        render :edit, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    @client = @delivery.order.client
    @addresses = @client.delivery_addresses.order(:description)
    @order = @delivery.order
    flash.now[:alert] = "Error al actualizar la entrega: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  # POST /deliveries
  def create
    ActiveRecord::Base.transaction do
      # 1. Cliente
      client = find_or_create_client

      # 2. Dirección
      address = find_or_create_address(client)

      # 3. Pedido
      order = find_or_create_order(client)

      # 4. Procesar los delivery_items y crear order_items si es necesario
      processed_delivery_items = process_delivery_items_params(order)

      # 5. Crear la entrega
      delivery_attrs = delivery_params.except(:delivery_items_attributes).merge(
        order: order,
        delivery_address: address,
        status: :ready_to_deliver
      )

      @delivery = Delivery.new(delivery_attrs)

      # 6. Asignar los delivery_items procesados
      @delivery.delivery_items = processed_delivery_items

      @delivery.save!
      redirect_to(session.delete(:deliveries_return_to) || deliveries_path,
                  notice: "Entrega creada correctamente.")
    end
  rescue ActiveRecord::RecordInvalid => e
    @delivery = e.record if e.respond_to?(:record) && e.record.is_a?(Delivery)
    @delivery ||= Delivery.new # Asegurar que @delivery existe
    @client = @order&.client || Client.new
    @order = @order || Order.new
    @clients = Client.all.order(:name)
    @addresses = @client.delivery_addresses.to_a
    flash.now[:alert] = "Error al crear la entrega: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  # GET /deliveries/by_week
  # Muestra un formulario simple para seleccionar semana y año
  def by_week
    # Guardar también esta URL para el retorno
    session[:deliveries_return_to] = request.fullpath

    @week = params[:week].to_i
    @year = params[:year].to_i

    # Si la semana es inválida, usa la semana actual
    @week = Date.today.cweek if @week < 1 || @week > 53
    @year = Date.today.cwyear if @year < 2000 # o el rango que prefieras

    start_date = Date.commercial(@year, @week, 1)
    @deliveries = Delivery.for_week(start_date)
                          .includes(order: :client, delivery_address: {}, delivery_items: {})
                          .order("deliveries.delivery_date ASC")
                          .page(params[:page])
    render :index
  end

  # PATCH /deliveries/:id/mark_as_delivered
  def mark_as_delivered
    @delivery.mark_as_delivered!
    redirect_to(session.delete(:deliveries_return_to) || deliveries_path,
                notice: "Entrega marcada como completada.")
  end

  # GET /deliveries/service_cases
  # Muestra solo las entregas que contienen casos de servicio
  def service_cases
    # Guardar también esta URL para el retorno
    session[:deliveries_return_to] = request.fullpath

    @deliveries = Delivery
      .joins(order: :client)
      .merge(Delivery.with_service_cases)
      .includes(:order, :delivery_address, :delivery_items)
      .order("deliveries.delivery_date ASC, clients.name ASC")
      .page(params[:page])
    render :index # Reutiliza la vista index
  end

  # GET /deliveries/addresses_for_client
  # AJAX endpoint para obtener direcciones de un cliente
  def addresses_for_client
    client = Client.find(params[:client_id])
    addresses = client.delivery_addresses.select(:id, :address)
    render json: addresses
  end

  # GET /deliveries/orders_for_client
  # AJAX endpoint para obtener pedidos de un cliente
  def orders_for_client
    client = Client.find(params[:client_id])
    orders = client.orders.select(:id, :number)
    render json: orders
  end

  def confirm_all_items
    authorize @delivery, :edit? # O crea una policy específica si lo prefieres

    updated = @delivery.delivery_items.where(status: [ :pending, :confirmed ]).update_all(status: :confirmed, updated_at: Time.current)
    @delivery.update_status_based_on_items

    redirect_to(session.delete(:deliveries_return_to) || deliveries_path,
                notice: "#{updated} productos confirmados para entrega.")
  end

  def reschedule_all
    authorize @delivery, :edit?
    new_date = params[:new_date].presence && Date.parse(params[:new_date])
    raise "Debes seleccionar una nueva fecha" unless new_date

    old_date   = @delivery.delivery_date
    old_status = @delivery.status.to_sym   # ✅ guardamos estado original

    raise "La nueva fecha debe ser diferente a la original" if new_date == old_date

    ActiveRecord::Base.transaction do
      # Crear la nueva entrega clonada
      new_delivery = @delivery.dup
      new_delivery.delivery_date = new_date
      new_delivery.status = old_status      # ✅ hereda el estado de la original
      new_delivery.save!

      # Limpiar items clonados
      new_delivery.delivery_items = []

      # Copiar los items no finalizados
      items_to_reschedule = @delivery.delivery_items.where.not(status: [ :delivered, :cancelled, :rescheduled ])
      items_to_reschedule.find_each do |item|
        DeliveryItem.create!(
          delivery: new_delivery,
          order_item: item.order_item,
          quantity_delivered: item.quantity_delivered,
          status: :pending,
          service_case: item.service_case
        )
        item.update!(status: :rescheduled)
      end

      # Dejar la entrega original marcada como rescheduled
      @delivery.update_column(:status, :rescheduled)   # ✅ queda histórico

      # Notificar
      users = User.where(role: [ :admin, :seller, :production_manager ])
      message = "La entrega del pedido #{@delivery.order.number} con fecha original de #{l old_date, format: :long} fue reagendada para el #{l new_date, format: :long}."
      NotificationService.create_for_users(users, new_delivery, message, type: "reschedule_delivery")

      redirect_to(session.delete(:deliveries_return_to) || deliveries_path,
                  notice: "Entrega reagendada para el #{l new_date, format: :long}.")
    end
  rescue => e
    redirect_to(session[:deliveries_return_to] || deliveries_path,
                alert: "Error al reagendar: #{e.message}")
  end

  def new_internal_delivery
    @delivery = Delivery.new(
      delivery_type: :internal_delivery,
      status: :scheduled,
      delivery_date: Date.current
    )

    # Construir los objetos anidados para que funcione el simple_fields_for
    delivery_item = @delivery.delivery_items.build
    delivery_item.build_order_item

    authorize @delivery
  end

  def create_internal_delivery
    ActiveRecord::Base.transaction do
      # 1. Crear o buscar cliente interno de la empresa
      company_client = Client.find_or_create_by!(name: "NaLakalu Interno") do |client|
        client.email = "interno@nalakalu.com"
        client.phone = "0000-0000"
      end

      # 2. Crear o buscar seller interno
      company_seller = Seller.find_or_create_by!(seller_code: "NALAKALU_INT") do |seller|
        seller.user = current_user
        seller.name = "Logística Interna"
      end

      # 3. Crear orden interna con número único
      order_number = "MANDADO"
      internal_order = Order.create!(
        client: company_client,
        seller: company_seller,
        number: order_number,
        status: :ready_for_delivery  # ✅ Correcto para Order
      )

      # 4. Crear dirección de entrega
      delivery_address = if params[:delivery_address].present? && params[:delivery_address][:address].present?
        company_client.delivery_addresses.create!(
          params.require(:delivery_address).permit(:address, :description, :latitude, :longitude, :plus_code)
        )
      else
        company_client.delivery_addresses.find_or_create_by!(address: "Oficinas Centrales NaLakalu") do |addr|
          addr.description = "Dirección por defecto para mandados internos"
        end
      end

      # 5. Procesar los delivery_items anidados
      processed_delivery_items = process_internal_delivery_items(internal_order)

      # 6. Crear la entrega
      @delivery = Delivery.new(
        internal_delivery_params.merge(
          delivery_type: :internal_delivery,
          status: :ready_to_deliver,  # ✅ Correcto para Delivery
          order: internal_order,
          delivery_address: delivery_address
        )
      )

      # 7. Asignar los delivery_items procesados
      @delivery.delivery_items = processed_delivery_items
      @delivery.save!

      redirect_to deliveries_path, notice: "Mandado interno creado correctamente."
    end
  rescue ActiveRecord::RecordInvalid => e
    # Reconstruir los objetos anidados para el formulario en caso de error
    @delivery ||= Delivery.new(delivery_type: :internal_delivery)
    if @delivery.delivery_items.empty?
      delivery_item = @delivery.delivery_items.build
      delivery_item.build_order_item
    end

    flash.now[:alert] = "Error al crear el mandado interno: #{e.message}"
    render :new_internal_delivery, status: :unprocessable_entity
  end

  def new_service_case
    @delivery = Delivery.new(
      delivery_type: :pickup, # Valor por defecto
      status: :scheduled,
      delivery_date: Date.current
    )
    @delivery.delivery_items.build.build_order_item

    @clients = Client.all.order(:name)
    @addresses = []
    @order = nil

    authorize @delivery
    render :new_service_case
  end

  def create_service_case
    ActiveRecord::Base.transaction do
      # 1. Cliente
      client = find_or_create_client

      # 2. Dirección
      address = find_or_create_address(client)

      # 3. Pedido
      order = find_or_create_order(client)

      # 4. Procesar delivery items
      processed_items = process_delivery_items_params(order)

      # 5. Crear la entrega con tipo explicitado (pickup, return_delivery, onsite_repair)
      @delivery = Delivery.new(
        delivery_params.except(:delivery_items_attributes).merge(
          order: order,
          delivery_address: address,
          status: :scheduled,
          delivery_type: params[:delivery][:delivery_type] # importante
        )
      )
      @delivery.delivery_items = processed_items
      @delivery.save!

      redirect_to deliveries_path, notice: "Caso de servicio creado correctamente."
    end
  rescue ActiveRecord::RecordInvalid => e
    @delivery = e.record if e.respond_to?(:record) && e.record.is_a?(Delivery)
    @delivery ||= Delivery.new(delivery_type: params[:delivery][:delivery_type] || :pickup)
    @clients = Client.all.order(:name)
    @addresses = @delivery.order&.client&.delivery_addresses || []
    @order = @delivery.order
    flash.now[:alert] = "Error al crear el caso de servicio: #{e.message}"
    render :new_service_case, status: :unprocessable_entity
  end

  private

  # Nuevo método para procesar delivery_items de mandados internos
  def process_internal_delivery_items(order)
    delivery_items = []

    return delivery_items unless params[:delivery][:delivery_items_attributes]

    params[:delivery][:delivery_items_attributes].each do |key, item_params|
      next if item_params[:_destroy] == "1"

      # Para mandados internos, siempre creamos nuevos items
      if item_params[:order_item_attributes].present?
        oi_params = item_params[:order_item_attributes]
        next if oi_params[:product].blank?

        # Crear el order_item
        order_item = order.order_items.create!(
          product: oi_params[:product],
          quantity: 1, # Los mandados siempre son cantidad 1
          status: :ready
        )

        # Crear el delivery_item
        delivery_item = DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: 1,
          status: :confirmed
        )

        delivery_items << delivery_item
      end
    end

    delivery_items
  end

  # Actualizar los parámetros permitidos para mandados internos
  def internal_delivery_params
    params.require(:delivery).permit(
      :delivery_date, :contact_name, :contact_phone, :delivery_notes, :delivery_time_preference,
      delivery_items_attributes: [
        :id, :_destroy,
        order_item_attributes: [ :id, :product ]
      ]
    )
  end

  private

  # Procesa los parámetros de delivery_items (existentes y nuevos)
  def process_delivery_items_params(order)
    delivery_items = []

    return delivery_items unless params[:delivery][:delivery_items_attributes]

    params[:delivery][:delivery_items_attributes].each do |key, item_params|
      next if item_params[:_destroy] == "1"

      if item_params[:id].present?
        # CASO UPDATE: delivery_item existente
        di = DeliveryItem.find(item_params[:id])

        # Actualizar delivery_item
        di.update!(
          quantity_delivered: item_params[:quantity_delivered] || di.quantity_delivered,
          service_case: item_params[:service_case] == "1",
          status: item_params[:status] || di.status
        )

        # También actualizar order_item si cambió
        if item_params[:order_item_attributes].present?
          oi_params = item_params[:order_item_attributes]
          if oi_params[:id].present?
            order_item = OrderItem.find(oi_params[:id])
            order_item.update!(
              product: oi_params[:product] || order_item.product,
              quantity: oi_params[:quantity] || order_item.quantity,
              notes: oi_params[:notes] || order_item.notes
            )
          end
        end

        delivery_items << di
      else
        # CASO NUEVO: crear delivery_item
        next if item_params[:order_item_attributes][:product].blank?

        # Buscar o crear el order_item
        order_item = find_or_create_order_item(order, item_params[:order_item_attributes])

        # Crear el delivery_item
        delivery_item = DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: item_params[:quantity_delivered] || 1,
          service_case: item_params[:service_case] == "1",
          status: :pending
        )

        delivery_items << delivery_item
      end
    end

    delivery_items
  end

  # Busca o crea un order_item para la orden
  def find_or_create_order_item(order, order_item_params)
    # Si tiene ID, es un order_item existente
    if order_item_params[:id].present?
      order_item = OrderItem.find(order_item_params[:id])
      order_item.update!(order_item_params.except(:id))
      return order_item
    end

    # Buscar si ya existe un order_item con el mismo producto en esta orden
    existing_item = order.order_items.find_by(product: order_item_params[:product])

    if existing_item
      # LÓGICA ACUMULATIVA: Si el item ya existe, sumar cantidades
      if order_item_params[:quantity].present? &&
        existing_item.quantity != order_item_params[:quantity].to_i

        new_quantity = existing_item.quantity.to_i + order_item_params[:quantity].to_i

        # Combinar notas si hay nuevas
        combined_notes = if order_item_params[:notes].present? && order_item_params[:notes] != existing_item.notes
          [ existing_item.notes, order_item_params[:notes] ].compact.reject(&:blank?).join("; ")
        else
          existing_item.notes || order_item_params[:notes]
        end

        existing_item.update!(
          quantity: new_quantity,
          notes: combined_notes
        )
      elsif order_item_params[:notes].present? && order_item_params[:notes] != existing_item.notes
        # Solo actualizar notas si la cantidad es la misma pero hay notas nuevas
        combined_notes = [ existing_item.notes, order_item_params[:notes] ].compact.reject(&:blank?).join("; ")
        existing_item.update!(notes: combined_notes)
      end
      return existing_item
    end

    # Crear nuevo order_item, asegurando el order_id correcto
    order.order_items.create!(
      product: order_item_params[:product],
      quantity: order_item_params[:quantity] || 1,
      notes: order_item_params[:notes],
      status: :in_production # o :pending, según tu enum final
    )
  end

  # Busca o crea un cliente
  def find_or_create_client
    if params[:client_id].present?
      Client.find(params[:client_id])
    else
      existing = Client.find_by(email: params[:client][:email]) if params[:client][:email].present?
      existing ||= Client.find_by(phone: params[:client][:phone]) if params[:client][:phone].present?
      existing || Client.create!(params.require(:client).permit(:name, :phone, :email))
    end
  end

  # Busca o crea una dirección de entrega
  def find_or_create_address(client)
    if params[:delivery] && params[:delivery][:delivery_address_id].present?
      addr = DeliveryAddress.find(params[:delivery][:delivery_address_id])

      # Si vienen campos para actualizar la dirección existente
      if params[:delivery_address].present?
        addr.update(
          params.require(:delivery_address)
                .permit(:address, :description, :latitude, :longitude, :plus_code)
        )
      end

      addr
    elsif params[:delivery_address] && params[:delivery_address][:address].present?
      existing = client.delivery_addresses.find_by(address: params[:delivery_address][:address])
      existing || client.delivery_addresses.create!(
        params.require(:delivery_address)
              .permit(:address, :description, :latitude, :longitude, :plus_code)
              .merge(client: client)
      )
    else
      raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debes seleccionar o ingresar una dirección."
    end
  end

  # Busca o crea un pedido
  def find_or_create_order(client)
    if params[:delivery] && params[:delivery][:order_id].present?
      Order.find(params[:delivery][:order_id])
    elsif params[:order] && params[:order][:number].present?
      existing_order = client.orders.find_by(number: params[:order][:number])
      return existing_order if existing_order

      client.orders.create!(
        number: params[:order][:number],
        seller_id: params[:seller_id] || current_user.seller&.id,
        status: :in_production
      )
    elsif params[:order_id].present?
      Order.find(params[:order_id])
    else
      raise ActiveRecord::RecordInvalid.new(Order.new), "Debes seleccionar o crear un pedido."
    end
  end

  # Busca la entrega por ID
  def set_delivery
    @delivery = Delivery.find(params[:id])
  end

  def set_addresses
    if @delivery&.order&.client
      @addresses = @delivery.order.client.delivery_addresses.to_a
    else
      @addresses = []
    end
  end

  # Parámetros permitidos para delivery
  def delivery_params
    params.require(:delivery).permit(
      :delivery_date, :delivery_address_id, :contact_name, :contact_phone, :delivery_notes, :delivery_type, :delivery_time_preference,
      delivery_items_attributes: [
        :id, :quantity_delivered, :service_case, :status, :_destroy,
        order_item_attributes: [ :id, :product, :quantity, :notes ]
      ]
    )
  end
end
