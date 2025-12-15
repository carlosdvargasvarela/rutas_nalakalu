# app/controllers/deliveries_controller.rb
class DeliveriesController < ApplicationController
  before_action :set_delivery, only: [:show, :edit, :update, :mark_as_delivered, :confirm_all_items, :reschedule_all, :approve, :note, :archive, :new_service_case_for_existing]
  before_action :set_addresses, only: [:new, :edit, :create, :update]

  # GET /deliveries
  def index
    session[:deliveries_return_to] = request.fullpath

    base_scope = (params[:show_rescheduled] == "1") ? Delivery.all : Delivery.where.not(status: :rescheduled)

    if params[:no_plan].present?
      base_scope = base_scope.where.not(id: DeliveryPlanAssignment.select(:delivery_id))
    end

    if (dq = params.dig(:q, :delivery_date_lt)).present?
      base_scope = begin
        base_scope.where("delivery_date < ?", dq.to_date)
      rescue
        base_scope
      end
    end

    excluded_statuses = %i[delivered rescheduled cancelled archived failed]
    base_scope = base_scope.where.not(status: excluded_statuses) if params[:no_plan].present?

    # 🔹 Filtrar solo casos de servicio
    if params[:only_service_cases].present?
      base_scope = base_scope.service_cases
    end

    @q = base_scope.ransack(params[:q])
    deliveries_scope = @q.result.includes(order: [:client, :seller], delivery_address: :client)

    @deliveries = deliveries_scope.order(delivery_date: :asc).page(params[:page])
    @all_deliveries = deliveries_scope.includes(delivery_items: {order_item: :order}).order(delivery_date: :asc)

    authorize Delivery

    respond_to do |format|
      format.html
      format.xlsx { response.headers["Content-Disposition"] = "attachment; filename=entregas_#{Date.today.strftime("%Y%m%d")}.xlsx" }
      format.csv { send_data @all_deliveries.to_csv, filename: "entregas_#{Date.today.strftime("%Y%m%d")}.csv" }
    end
  end

  def show
    @future_deliveries = Delivery
      .where(order_id: @delivery.order_id, delivery_address_id: @delivery.delivery_address_id)
      .where.not(id: @delivery.id)
      .where(status: [:scheduled, :ready_to_deliver, :in_plan, :in_route])

    @delivery_history = @delivery.delivery_history
  end

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

    @clients = Client.all.order(:name)
    @addresses = (@client&.delivery_addresses || []).to_a
    @orders = (@client&.orders || []).to_a
  end

  def edit
    @client = @delivery.order.client
    @order = @delivery.order

    @addresses = @client.delivery_addresses.to_a
    @orders = @client.orders.to_a
    @clients = [@client]

    @delivery.delivery_items.build.build_order_item if @delivery.delivery_items.empty?
  end

  # POST /deliveries
  def create
    authorize Delivery
    sanitize_delivery_address_param!
    sanitize_order_id_param!
    @delivery = Deliveries::Creator.new(params: params, current_user: current_user).call
    redirect_to @delivery, notice: "Entrega creada correctamente."
  rescue => e
    handle_create_error(e)
  end

  # PATCH/PUT /deliveries/:id
  def update
    authorize @delivery, :edit?
    sanitize_delivery_address_param!
    sanitize_order_id_param!
    @delivery = Deliveries::Updater.new(delivery: @delivery, params: params, current_user: current_user).call
    redirect_to @delivery, notice: "Entrega actualizada correctamente."
  rescue => e
    handle_update_error(e)
  end

  def reschedule_all
    authorize @delivery, :edit?
    reason = params[:reason]

    target_delivery = Deliveries::Rescheduler.new(
      delivery: @delivery,
      new_date: safe_date(params[:new_date]),
      current_user: current_user,
      reason: reason
    ).call

    redirect_to(
      session.delete(:deliveries_return_to) || delivery_path(target_delivery),
      notice: "Entrega reagendada para el #{target_delivery.delivery_date.strftime("%d/%m/%Y")}."
    )
  rescue => e
    redirect_to(session[:deliveries_return_to] || deliveries_path, alert: "Error al reagendar: #{e.message}")
  end

  def new_internal_delivery
    @delivery = Delivery.new(
      delivery_type: :internal_delivery,
      status: :scheduled,
      delivery_date: Date.current
    )

    delivery_item = @delivery.delivery_items.build
    delivery_item.build_order_item

    authorize @delivery
  end

  def create_internal_delivery
    authorize Delivery
    @delivery = Deliveries::InternalCreator.new(params: params, current_user: current_user).call
    redirect_to deliveries_path, notice: "Mandado interno creado correctamente."
  rescue => e
    handle_internal_error(e)
  end

  def new_service_case
    @delivery = Delivery.new(
      delivery_type: :pickup_with_return,
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
    authorize Delivery
    @delivery = Deliveries::ServiceCaseCreator.new(params: params, current_user: current_user).call
    redirect_to deliveries_path, notice: "Caso de servicio creado correctamente."
  rescue => e
    handle_service_case_error(e)
  end

  def new_service_case_for_existing
    authorize @delivery, :edit?

    @service_case = Delivery.new(
      order: @delivery.order,
      delivery_address: @delivery.delivery_address,
      contact_name: @delivery.contact_name,
      contact_phone: @delivery.contact_phone,
      delivery_type: :pickup_with_return,
      delivery_date: Date.today,
      status: :scheduled
    )

    @addresses = @delivery.order.client.delivery_addresses.to_a

    @delivery.order.order_items.each do |oi|
      @service_case.delivery_items.build(
        order_item: oi,
        quantity_delivered: oi.quantity,
        service_case: true,
        status: :pending
      )
    end
  end

  def create_service_case_for_existing
    parent_delivery = Delivery.find(params[:id])
    authorize parent_delivery, :edit?

    service = Deliveries::ServiceCaseForExistingCreator.new(
      parent_delivery: parent_delivery,
      params: params,
      current_user: current_user
    )
    main = service.call
    created = service.created_deliveries

    if created.size == 1
      redirect_to delivery_path(main),
        notice: "Se creó un caso de servicio (#{main.display_type}) para el #{I18n.l main.delivery_date, format: :long}."
    else
      pickup, ret = created
      redirect_to delivery_path(main),
        notice: "Se crearon 2 entregas de caso de servicio: " \
                "Recogida (#{I18n.l pickup.delivery_date, format: :long}) y " \
                "Devolución (#{I18n.l ret.delivery_date, format: :long})."
    end
  rescue => e
    handle_service_case_existing_error(e, parent_delivery)
  end

  def confirm_all_items
    authorize @delivery, :edit?
    updated = @delivery.delivery_items.where(status: :pending).update_all(status: :confirmed, updated_at: Time.current)
    @delivery.mark_as_confirmed_by_vendor!
    @delivery.update_status_based_on_items
    redirect_to(session.delete(:deliveries_return_to) || delivery_path(@delivery), notice: "#{updated} productos confirmados para entrega.")
  end

  def mark_as_delivered
    @delivery.mark_as_delivered!
    @delivery.update_status_based_on_items
    redirect_to @delivery, notice: "Entrega marcada como completada."
  end

  def approve
    authorize @delivery, :approve?
    @delivery.approve!
    redirect_to @delivery, notice: "Entrega aprobada correctamente para esta semana."
  end

  def archive
    if @delivery.update(status: :archived)
      redirect_to @delivery, notice: "La entrega fue archivada correctamente."
    else
      redirect_to @delivery, alert: "No se pudo archivar la entrega."
    end
  end

  def by_week
    session[:deliveries_return_to] = request.fullpath
    @week = (1..53).cover?(params[:week].to_i) ? params[:week].to_i : Date.today.cweek
    @year = (params[:year].to_i >= 2000) ? params[:year].to_i : Date.today.cwyear
    start_date = Date.commercial(@year, @week, 1)
    @deliveries = Delivery.for_week(start_date).includes(order: :client, delivery_address: {}, delivery_items: {}).order("deliveries.delivery_date ASC").page(params[:page])
    render :index
  end

  def service_cases
    session[:deliveries_return_to] = request.fullpath
    @deliveries = Delivery.joins(order: :client).merge(Delivery.with_service_cases).includes(:order, :delivery_address, :delivery_items).order("deliveries.delivery_date ASC, clients.name ASC").page(params[:page])
    render :index
  end

  def addresses_for_client
    client = Client.find(params[:client_id])
    render json: client.delivery_addresses.select(:id, :address)
  end

  def orders_for_client
    client = Client.find(params[:client_id])
    render json: client.orders.select(:id, :number)
  end

  def note
    render partial: "delivery_items/form_note", locals: {delivery: @delivery}
  end

  private

  def set_delivery
    @delivery = Delivery.find(params[:id])
  end

  def set_addresses
    @addresses = @delivery&.order&.client&.delivery_addresses&.to_a || []
  end

  def sanitize_delivery_address_param!
    raw = params.dig(:delivery, :delivery_address_id).to_s
    params[:delivery][:delivery_address_id] = nil if raw == "__new__" || raw.blank?
  rescue
    # noop
  end

  def sanitize_order_id_param!
    raw = params.dig(:delivery, :order_id).to_s
    params[:delivery][:order_id] = nil if raw == "__new__" || raw.blank?
  rescue
    # noop
  end

  def safe_date(str)
    str.present? ? Date.parse(str) : nil
  end

  def find_or_initialize_client_from_params
    if params[:client_id].present?
      Client.find(params[:client_id])
    elsif params[:client].present?
      Client.new(params.require(:client).permit(:name, :phone, :email))
    else
      Client.new
    end
  end

  def find_or_initialize_order_from_params(client)
    raw_order_id = params.dig(:delivery, :order_id).to_s.strip
    if raw_order_id.present? && raw_order_id != "__new__"
      client.orders.find_by(id: raw_order_id) || Order.new
    elsif params[:order].present?
      client.orders.build(params.require(:order).permit(:number, :seller_id))
    else
      Order.new
    end
  end

  def handle_create_error(e)
    Rails.logger.error "Error crear entrega: #{e.message}"
    @delivery ||= Delivery.new
    if params[:delivery].present?
      permitted = params.require(:delivery).permit(
        :delivery_date, :delivery_address_id, :order_id,
        :contact_name, :contact_phone, :delivery_notes, :delivery_type, :delivery_time_preference,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :service_case, :status, :notes, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
      permitted[:delivery_address_id] = nil if permitted[:delivery_address_id].to_s == "__new__"
      permitted[:order_id] = nil if permitted[:order_id].to_s == "__new__"
      @delivery.assign_attributes(permitted)
    end

    @client = find_or_initialize_client_from_params
    @order = find_or_initialize_order_from_params(@client)
    @addresses = @client.delivery_addresses.to_a
    @clients = Client.all.order(:name)

    flash.now[:alert] = "Error al crear la entrega: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  def handle_update_error(e)
    if params[:delivery].present?
      permitted = params.require(:delivery).permit(
        :delivery_date, :delivery_address_id, :order_id,
        :contact_name, :contact_phone, :delivery_notes, :delivery_type, :delivery_time_preference,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :service_case, :status, :notes, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
      permitted[:delivery_address_id] = nil if permitted[:delivery_address_id].to_s == "__new__"
      permitted[:order_id] = nil if permitted[:order_id].to_s == "__new__"
      @delivery.assign_attributes(permitted)
    end

    @order = @delivery.order
    @client = @order.client
    @addresses = @client.delivery_addresses.order(:description)
    flash.now[:alert] = "Error al actualizar la entrega: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  def handle_service_case_error(e)
    @delivery ||= Delivery.new
    @delivery.delivery_type ||= params.dig(:delivery, :delivery_type) || :pickup
    @delivery.status ||= :scheduled

    if params[:delivery].present?
      permitted = params.require(:delivery).permit(
        :delivery_date, :delivery_address_id, :order_id,
        :contact_name, :contact_phone, :delivery_notes, :delivery_type, :delivery_time_preference,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :status, :notes, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
      permitted[:delivery_address_id] = nil if permitted[:delivery_address_id].to_s == "__new__"
      permitted[:order_id] = nil if permitted[:order_id].to_s == "__new__"
      @delivery.assign_attributes(permitted)
    end

    @client = if params[:client_id].present?
      Client.find_by(id: params[:client_id])
    elsif params[:client].present?
      Client.new(params.require(:client).permit(:name, :phone, :email))
    else
      @delivery.order&.client || Client.new
    end

    raw_order_id = @delivery.order_id.to_s.strip
    if raw_order_id.present? && raw_order_id != "__new__"
      @order = Order.find_by(id: raw_order_id)
    elsif params[:order].present?
      permitted_order = params.require(:order).permit(:number, :seller_id)
      @order = @client ? @client.orders.build(permitted_order) : Order.new(permitted_order)
    else
      @order = @delivery.order || Order.new
    end

    @clients = Client.all.order(:name)
    @addresses = @client.present? ? @client.delivery_addresses.to_a : []
    @order ||= @delivery.order

    flash.now[:alert] = "Error al crear el caso de servicio: #{e.message}"
    render :new_service_case, status: :unprocessable_entity
  end

  def handle_service_case_existing_error(e, parent_delivery)
    Rails.logger.error("Error ServiceCaseExisting: #{e.message}")
    @delivery = parent_delivery

    @service_case ||= Delivery.new(
      order: parent_delivery.order,
      delivery_address: parent_delivery.delivery_address
    )

    if params[:delivery].present?
      permitted = params.require(:delivery).permit(
        :delivery_date, :delivery_type, :delivery_address_id,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
      permitted[:delivery_address_id] = nil if permitted[:delivery_address_id].to_s == "__new__"
      @service_case.assign_attributes(permitted)

      if @service_case.delivery_type.is_a?(String)
        @service_case.delivery_type = @service_case.delivery_type.to_sym
      end
      if (dd = params.dig(:delivery, :delivery_date)).present?
        @service_case.delivery_date = begin
          Date.parse(dd)
        rescue
          @service_case.delivery_date
        end
      end
    else
      @service_case.delivery_type ||= :pickup_with_return
      @service_case.delivery_date ||= Date.current
    end

    if params.dig(:delivery, :delivery_address_id).present?
      if params[:delivery][:delivery_address_id].to_s != "__new__"
        @service_case.delivery_address = DeliveryAddress.find_by(id: params[:delivery][:delivery_address_id]) || parent_delivery.delivery_address
      else
        @service_case.delivery_address ||= parent_delivery.delivery_address
      end
    else
      @service_case.delivery_address ||= parent_delivery.delivery_address
    end

    @addresses = parent_delivery.order.client.delivery_addresses.to_a

    if @service_case.delivery_items.blank?
      if params.dig(:delivery, :delivery_items_attributes).present?
        params[:delivery][:delivery_items_attributes].each_value do |di_attrs|
          next if di_attrs.is_a?(String)
          oi_id = di_attrs[:order_item_id].presence
          oi = oi_id.present? ? OrderItem.find_by(id: oi_id) : nil

          @service_case.delivery_items.build(
            order_item: oi,
            quantity_delivered: (di_attrs[:quantity_delivered].presence || 1).to_i,
            service_case: true,
            status: :pending
          )
        end
      else
        parent_delivery.order.order_items.each do |oi|
          @service_case.delivery_items.build(
            order_item: oi,
            quantity_delivered: oi.quantity,
            service_case: true,
            status: :pending
          )
        end
      end
    end

    flash.now[:alert] = "Error al generar caso de servicio: #{e.message}"
    render :new_service_case_for_existing, status: :unprocessable_entity
  end

  def handle_internal_error(e)
    Rails.logger.error "Error crear mandado interno: #{e.message}"
    @delivery ||= Delivery.new(delivery_type: :internal_delivery, status: :scheduled, delivery_date: Date.current)
    flash.now[:alert] = "Error al crear el mandado interno: #{e.message}"
    render :new_internal_delivery, status: :unprocessable_entity
  end
end
