# app/controllers/deliveries_controller.rb

# CRUD + acciones operativas sobre {Delivery}: aprobar, marcar entregado,
# bodegaje, dividir, reagendar, casos de servicio/reparación (nuevos y sobre
# una entrega existente), retiro en sala, movimientos de showroom y mandados
# internos. La mayoría de las acciones de escritura responden tanto HTML
# (redirect) como turbo_stream (ver {#render_delivery_update_stream}, que
# centraliza el refresco del panel de detalle + tarjeta de índice).
class DeliveriesController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_delivery, only: [
    :show, :edit, :update, :mark_as_delivered, :confirm_all_items,
    :reschedule_form, :reschedule_all, :approve, :note, :archive, :new_service_case_for_existing,
    :update_status, :reassign_seller, :take_order, :sala_pickup_form,
    :create_sala_pickup, :service_case_form, :create_service_case_from_workspace,
    :warehousing_form, :start_warehousing, :end_warehousing, :unconfirm, :reopen,
    :split_form, :split,
    :new_repair_service_for_existing, :create_repair_service_for_existing,
    :repair_service_form, :create_repair_service_from_workspace,
    :propagate_to_associated
  ]
  before_action :set_addresses, only: [:new, :edit, :create, :update]

  def index
    authorize Delivery

    @sellers = Seller.order(:name)
    session[:deliveries_return_to] = request.fullpath

    excluded_from_index = []
    excluded_from_index << :rescheduled unless current_user.admin? && params[:show_rescheduled] == "1"
    excluded_from_index << :archived unless params[:show_archived] == "1"
    base_scope = Delivery.where.not(status: excluded_from_index)

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

    if params[:only_service_cases].present?
      base_scope = Delivery.filter_by_predicate(base_scope, :requires_service_case_action?)
    end

    if params[:only_repair_services].present?
      base_scope = Delivery.filter_by_predicate(base_scope, :requires_repair_service_action?)
    end

    @q = base_scope.ransack(params[:q])
    deliveries_scope = @q.result.includes(order: [:client, :seller, :order_contacts], delivery_address: :client, delivery_plan_assignment: :delivery_plan)

    @deliveries = deliveries_scope.order(delivery_date: :asc).page(params[:page]).per(5)

    @all_deliveries = deliveries_scope
      .includes(delivery_items: {order_item: :order})
      .order(delivery_date: :asc)

    respond_to do |format|
      format.html
      format.xlsx { response.headers["Content-Disposition"] = "attachment; filename=entregas_#{Date.current.strftime("%Y%m%d")}.xlsx" }
      format.csv { send_data @all_deliveries.to_csv, filename: "entregas_#{Date.current.strftime("%Y%m%d")}.csv" }
    end
  end

  def show
    authorize @delivery
    load_delivery_for_panel
    set_delivery_panel_data

    if turbo_frame_request?
      render layout: false
    end
  end

  def new
    authorize Delivery
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
    authorize @delivery, :edit?
    @client = @delivery.order.client
    @order = @delivery.order

    @addresses = @client.delivery_addresses.to_a
    @orders = @client.orders.to_a
    @clients = [@client]

    @delivery.delivery_items.build.build_order_item if @delivery.delivery_items.empty?
  end

  def create
    authorize Delivery
    sanitize_delivery_address_param!
    sanitize_order_id_param!
    @delivery = Deliveries::Creator.new(params: params, current_user: current_user).call
    redirect_to @delivery, notice: "Entrega creada correctamente."
  rescue => e
    handle_create_error(e)
  end

  def update
    authorize @delivery, :edit?
    sanitize_delivery_address_param!
    sanitize_order_id_param!
    @delivery = Deliveries::Updater.new(delivery: @delivery, params: params, current_user: current_user).call

    if (new_date_str = params.dig(:delivery, :reschedule_new_date)).present?
      @delivery = Deliveries::Rescheduler.new(
        delivery: @delivery,
        new_date: parse_date(new_date_str),
        current_user: current_user,
        reason: params.dig(:delivery, :reschedule_reason)
      ).call

      return redirect_to edit_delivery_path(@delivery),
        notice: "Entrega actualizada y reagendada para el #{@delivery.delivery_date.strftime("%d/%m/%Y")}."
    end

    respond_to do |format|
      format.turbo_stream { render_delivery_update_stream(notice: "Entrega actualizada correctamente.") }
      format.html do
        redirect_to(
          session[:deliveries_return_to] || deliveries_path,
          notice: "Entrega actualizada correctamente."
        )
      end
    end
  rescue => e
    handle_update_error(e)
  end

  def reschedule_form
    authorize @delivery, :edit?
    render layout: false
  end

  def reschedule_all
    authorize @delivery, :edit?
    reason = params[:reason]

    target_delivery = Deliveries::Rescheduler.new(
      delivery: @delivery,
      new_date: parse_date(params[:new_date]),
      current_user: current_user,
      reason: reason
    ).call

    redirect_to(
      session[:deliveries_return_to] || delivery_path(target_delivery),
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

  def approve
    authorize @delivery, :approve?
    @delivery.approve!

    # 🔹 Registrar evento
    DeliveryEvent.record(
      delivery: @delivery,
      action: "approved",
      actor: current_user,
      payload: {approved_at: Time.current.to_s}
    )

    respond_to do |format|
      format.turbo_stream do
        load_delivery_for_panel
        set_delivery_panel_data

        render turbo_stream: [
          turbo_stream.replace(
            dom_id(@delivery, :detail),
            partial: "deliveries/show_partials/detail_data",
            locals: {
              delivery: @delivery,
              future_deliveries: @future_deliveries,
              delivery_history: @delivery_history
            }
          ),
          turbo_stream.replace(
            dom_id(@delivery, :card),
            partial: "deliveries/index_partials/delivery_card",
            locals: {delivery: @delivery}
          )
        ]
      end
      format.html { redirect_to @delivery, notice: "Entrega aprobada correctamente para esta semana." }
    end
  rescue => e
    render_delivery_error_flash("Error al aprobar la entrega: #{e.message}")
  end

  def mark_as_delivered
    authorize @delivery, :edit?

    @delivery.mark_as_delivered!
    @delivery.reload

    # 🔹 Registrar evento
    DeliveryEvent.record(
      delivery: @delivery,
      action: "delivered",
      actor: current_user,
      payload: {delivered_at: Time.current.to_s}
    )

    respond_to do |format|
      format.turbo_stream do
        render_delivery_update_stream(notice: "Entrega marcada como completada.", include_product_table: true)
      end
      format.html { redirect_to @delivery, notice: "Entrega marcada como completada." }
    end
  rescue => e
    render_delivery_error_flash("Error al marcar la entrega como completada: #{e.message}")
  end

  def start_warehousing
    authorize @delivery, :edit?

    until_date = parse_date(params[:warehousing_until])

    unless until_date.present? && until_date > Date.current
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Debes indicar una fecha futura de fin de bodegaje."
          render turbo_stream: turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
            status: :unprocessable_entity
        end
      end
      return
    end

    @delivery.start_warehousing!(until_date)

    # 🔹 Registrar evento
    DeliveryEvent.record(
      delivery: @delivery,
      action: "warehousing_started",
      actor: current_user,
      payload: {
        warehousing_until: until_date.to_s,
        started_at: Time.current.to_s
      }
    )

    respond_to do |format|
      format.turbo_stream do
        render_delivery_update_stream(
          notice: "Entrega en bodegaje hasta el #{I18n.l until_date, format: :long}.",
          extra_streams: [turbo_stream.update("modal", "")]
        )
      end
      format.html { redirect_to @delivery, notice: "Entrega en bodegaje." }
    end
  rescue => e
    render_delivery_error_flash("Error al iniciar el bodegaje: #{e.message}")
  end

  def end_warehousing
    authorize @delivery, :edit?
    @delivery.end_warehousing!

    # 🔹 Registrar evento
    DeliveryEvent.record(
      delivery: @delivery,
      action: "warehousing_ended",
      actor: current_user,
      payload: {ended_at: Time.current.to_s}
    )

    respond_to do |format|
      format.turbo_stream do
        render_delivery_update_stream(notice: "Bodegaje finalizado. Entrega vuelve a estado pendiente.")
      end
      format.html { redirect_to @delivery, notice: "Bodegaje finalizado." }
    end
  rescue => e
    render_delivery_error_flash("Error al finalizar el bodegaje: #{e.message}")
  end

  def split_form
    authorize @delivery, :edit?
    @items = @delivery.delivery_items.bulk_reschedulable.includes(:order_item)

    if @items.empty?
      redirect_to delivery_path(@delivery), alert: "Esta entrega no tiene productos que se puedan dividir."
      return
    end

    @existing_deliveries = Delivery
      .where(order_id: @delivery.order_id, delivery_address_id: @delivery.delivery_address_id)
      .where("delivery_date >= ?", Date.current)
      .where.not(id: @delivery.id)
      .where.not(status: %i[rescheduled cancelled archived])
      .order(:delivery_date)
  end

  # Divide los productos "reschedulables" de la entrega entre una o más
  # entregas destino (existentes o nuevas por fecha), vía Deliveries::Splitter.
  def split
    authorize @delivery, :edit?

    count = Deliveries::Splitter.new(
      delivery:      @delivery,
      target_dates:  params[:target_dates].to_a,
      splits_params: params[:splits].to_unsafe_h,
      reason:        params[:reason].presence,
      current_user:  current_user
    ).call

    redirect_to delivery_path(@delivery), notice: "Entrega dividida: #{count} movimiento(s) realizados exitosamente."
  rescue => e
    redirect_to split_form_delivery_path(@delivery), alert: e.message
  end

  # Copia los campos indicados (ver DeliveryGroup::PROPAGATABLE_FIELDS) de
  # esta entrega hacia otras entregas del mismo delivery_group. Responde JSON
  # (usado desde un modal AJAX).
  def propagate_to_associated
    authorize @delivery, :update?

    fields     = Array(params[:fields]).select { |f| DeliveryGroup::PROPAGATABLE_FIELDS.key?(f) }
    target_ids = Array(params[:delivery_ids]).map(&:to_i)
    valid_ids  = @delivery.associated_deliveries.pluck(:id)
    target_ids &= valid_ids

    if fields.empty?
      return render json: { error: "Seleccioná al menos un campo para propagar." }, status: :unprocessable_entity
    end

    if target_ids.empty?
      return render json: { error: "Seleccioná al menos una entrega destino." }, status: :unprocessable_entity
    end

    values = @delivery.attributes.slice(*fields)
    Delivery.transaction do
      Delivery.where(id: target_ids).each { |d| d.update!(values) }
    end

    render json: { updated_count: target_ids.size }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "No se pudo propagar: #{e.message}" }, status: :unprocessable_entity
  end

  def reassign_seller
    authorize @delivery, :reassign_seller?

    seller_id = params[:seller_id].presence
    unless seller_id
      redirect_to delivery_path(@delivery), alert: "Debes seleccionar un vendedor."
      return
    end

    old_seller = @delivery.order.seller
    seller = Seller.find(seller_id)
    @delivery.order.reassign_to_seller!(seller)

    # 🔹 Registrar evento
    DeliveryEvent.record(
      delivery: @delivery,
      action: "seller_reassigned",
      actor: current_user,
      payload: {
        old_seller_id: old_seller&.id,
        old_seller_name: old_seller&.name,
        new_seller_id: seller.id,
        new_seller_name: seller.name,
        new_seller_code: seller.seller_code
      }
    )

    redirect_to delivery_path(@delivery),
      notice: "El pedido #{@delivery.order.number} fue reasignado al vendedor #{seller.name} (#{seller.seller_code})."
  rescue => e
    redirect_to delivery_path(@delivery),
      alert: "No se pudo reasignar el pedido: #{e.message}"
  end

  def create_internal_delivery
    authorize Delivery
    @delivery = Deliveries::InternalCreator.new(params: params, current_user: current_user).call
    redirect_to deliveries_path, notice: "Mandado interno creado correctamente."
  rescue => e
    handle_internal_error(e)
  end

  def new_showroom_movement
    @showrooms = Showroom.order(:name)
    @delivery = Delivery.new(
      delivery_type: :showroom,
      status: :scheduled,
      delivery_date: Date.current
    )
    @delivery.delivery_items.build.build_order_item
    authorize @delivery
  end

  def create_showroom_movement
    authorize Delivery
    deliveries = Deliveries::ShowroomMovementCreator.new(params: params, current_user: current_user).call
    notice = deliveries.size > 1 \
      ? "Movimiento inter-sala registrado: #{deliveries.size} entregas creadas correctamente." \
      : "Movimiento de showroom registrado correctamente."
    redirect_to deliveries_path, notice: notice
  rescue => e
    @showrooms = Showroom.order(:name)
    @delivery ||= Delivery.new(delivery_type: :showroom, status: :scheduled, delivery_date: Date.current)
    @delivery.delivery_items.build.build_order_item if @delivery.delivery_items.empty?
    flash.now[:alert] = "Error al registrar el movimiento: #{e.message}"
    render :new_showroom_movement, status: :unprocessable_entity
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

  def new_repair_service
    @delivery = Delivery.new(
      delivery_type: :repair_pickup,
      status: :scheduled,
      delivery_date: Date.current
    )
    @delivery.delivery_items.build.build_order_item

    @clients = Client.all.order(:name)
    @addresses = []

    authorize @delivery
    render :new_repair_service
  end

  def create_repair_service
    authorize Delivery
    deliveries = Deliveries::RepairServiceCreator.new(params: params, current_user: current_user).call
    notice = deliveries.size > 1 \
      ? "Servicio de reparación creado: retiro y entrega programados correctamente." \
      : "Servicio de reparación creado correctamente."
    redirect_to deliveries_path, notice: notice
  rescue => e
    handle_repair_service_error(e)
  end

  def new_service_case_for_existing
    authorize @delivery, :edit?

    @service_case = Delivery.new(
      order: @delivery.order,
      delivery_address: @delivery.delivery_address,
      contact_name: @delivery.contact_name,
      contact_phone: @delivery.contact_phone,
      delivery_type: :pickup_with_return,
      delivery_date: Date.current,
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
                "Retiro del producto (#{I18n.l pickup.delivery_date, format: :long}) y " \
                "Devolución (#{I18n.l ret.delivery_date, format: :long})."
    end
  rescue => e
    handle_service_case_existing_error(e, parent_delivery)
  end

  def new_repair_service_for_existing
    authorize @delivery, :edit?

    @repair_delivery = Delivery.new(
      order: @delivery.order,
      delivery_address: @delivery.delivery_address,
      contact_name: @delivery.contact_name,
      contact_phone: @delivery.contact_phone,
      delivery_type: :repair_pickup,
      delivery_date: Date.current,
      status: :scheduled
    )

    @addresses = @delivery.order.client.delivery_addresses.to_a

    @delivery.order.order_items.each do |oi|
      @repair_delivery.delivery_items.build(
        order_item: oi,
        quantity_delivered: oi.quantity,
        status: :pending
      )
    end
  end

  def create_repair_service_for_existing
    parent_delivery = @delivery
    authorize parent_delivery, :edit?

    service = Deliveries::RepairServiceForExistingCreator.new(
      parent_delivery: parent_delivery,
      params: params,
      current_user: current_user
    )
    main = service.call
    created = service.created_deliveries

    if created.size == 1
      redirect_to delivery_path(main),
        notice: "Se creó un servicio de reparación (#{main.display_type}) para el #{I18n.l main.delivery_date, format: :long}."
    else
      pickup, ret = created
      redirect_to delivery_path(main),
        notice: "Se crearon 2 entregas de servicio de reparación: " \
                "Retiro (#{I18n.l pickup.delivery_date, format: :long}) y " \
                "Entrega (#{I18n.l ret.delivery_date, format: :long})."
    end
  rescue => e
    handle_repair_service_existing_error(e, parent_delivery)
  end

  def sala_pickup_form
    authorize @delivery, :edit?
    @detector = Deliveries::SalaPickupDetector.new(@delivery)
    @items_by_sala = @detector.items_by_sala

    # Si vienen IDs por bulk, filtramos solo esos
    if params[:item_ids].present?
      ids = params[:item_ids].split(",").map(&:to_i)
      @items_by_sala.each do |sala, items|
        @items_by_sala[sala] = items.select { |i| ids.include?(i.id) }
      end
      @items_by_sala.reject! { |_, items| items.empty? }
    end

    # --- AGREGA ESTO AQUÍ ---
    # Inicializamos un objeto dummy para que simple_form y los partials de dirección no rompan
    @pickup_delivery = Delivery.new(
      delivery_date: @delivery.delivery_date - 1.day,
      contact_name: "Encargado de Sala",
      order: @delivery.order
    )
    # Construimos una dirección vacía asociada al cliente para evitar NOP sobre delivery_address
    @pickup_delivery.build_delivery_address(client: @delivery.order.client)

    # Cargamos las direcciones existentes del cliente para el select
    @addresses = @delivery.order.client.delivery_addresses.to_a

    # Datos de todos los showrooms para el selector del modal (serializado para Stimulus).
    @showrooms_data = Showroom.includes(:delivery_address).order(:name).map do |s|
      addr = s.delivery_address
      {
        code:        s.code,
        name:        s.name,
        has_address: addr.present?,
        address:     addr&.address,
        description: addr&.description,
        latitude:    addr&.latitude,
        longitude:   addr&.longitude,
        plus_code:   addr&.plus_code
      }
    end

    render layout: false
  end

  def create_sala_pickup
    authorize @delivery, :edit?

    @pickup_delivery = Deliveries::SalaPickupCreator.new(
      original_delivery: @delivery,
      params: params,
      current_user: current_user
    ).call

    respond_to do |format|
      format.turbo_stream do
        # 1. Cargamos el contexto del panel (setea @future_deliveries y @delivery_history)
        load_delivery_for_panel
        set_delivery_panel_data

        flash.now[:notice] = "Orden de retiro en sala para pedido ##{@pickup_delivery.order_number} registrada correctamente."

        render turbo_stream: [
          turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
          turbo_stream.update("modal", ""),
          turbo_stream.replace(
            dom_id(@delivery, :detail),
            partial: "deliveries/show_partials/detail_data",
            locals: {
              delivery: @delivery,
              # 2. Pasamos las variables requeridas por el partial
              future_deliveries: @future_deliveries,
              delivery_history: @delivery_history
            }
          )
        ]
      end
      format.html { redirect_to @delivery, notice: "Retiro en sala registrado." }
    end
  rescue => e
    handle_sala_pickup_error(e)
  end

  def warehousing_form
    authorize @delivery, :edit?

    respond_to do |format|
      format.html { render :warehousing_form }
    end
  end

  def service_case_form
    authorize @delivery, :edit?

    @detector = Deliveries::ServiceCaseDetector.new(@delivery)
    @items = @detector.actionable_items

    @service_delivery = Delivery.new(
      order: @delivery.order,
      delivery_address: @delivery.delivery_address,
      contact_name: @delivery.contact_name,
      contact_phone: @delivery.contact_phone,
      delivery_date: Date.current,
      delivery_type: :pickup_with_return
    )

    @addresses = @delivery.order.client.delivery_addresses.to_a

    render layout: false
  end

  # Acción "workspace" del caso de servicio: según params[:delivery][:mode]
  # registra solo una nota (devolucion/reparacion) o, si no hay mode, crea la
  # entrega de devolución real vía Deliveries::ServiceCaseFromWorkspaceCreator.
  def create_service_case_from_workspace
    authorize @delivery, :edit?

    notice_msg = case params.dig(:delivery, :mode)
    when "devolucion"
      register_devolucion_note
      "Nota de devolución registrada correctamente."
    when "reparacion"
      register_reparacion_note
      "Reparación en sitio registrada correctamente."
    else
      Deliveries::ServiceCaseFromWorkspaceCreator.new(
        original_delivery: @delivery,
        params: params,
        current_user: current_user
      ).call
      "Devolución agendada correctamente."
    end

    respond_to do |format|
      format.turbo_stream do
        load_delivery_for_panel
        set_delivery_panel_data

        flash.now[:notice] = notice_msg

        render turbo_stream: [
          turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
          turbo_stream.update("modal", ""),
          turbo_stream.replace(
            dom_id(@delivery, :detail),
            partial: "deliveries/show_partials/detail_data",
            locals: {
              delivery: @delivery,
              future_deliveries: @future_deliveries,
              delivery_history: @delivery_history
            }
          )
        ]
      end
    end
  end

  def repair_service_form
    authorize @delivery, :edit?

    @detector = Deliveries::RepairServiceDetector.new(@delivery)
    @items    = @detector.actionable_items

    @repair_delivery = Delivery.new(
      order:            @delivery.order,
      delivery_address: @delivery.delivery_address,
      contact_name:     @delivery.contact_name,
      contact_phone:    @delivery.contact_phone,
      delivery_date:    Date.current
    )

    @addresses = @delivery.order.client.delivery_addresses.to_a

    render layout: false
  end

  # Análogo a #create_service_case_from_workspace para servicio de reparación.
  def create_repair_service_from_workspace
    authorize @delivery, :edit?

    notice_msg = case params.dig(:delivery, :mode)
    when "repair_entrega"
      register_repair_entrega_note
      "Entrega de reparación registrada correctamente."
    else
      Deliveries::RepairServiceFromWorkspaceCreator.new(
        original_delivery: @delivery,
        params: params,
        current_user: current_user
      ).call
      "Entrega de reparación agendada correctamente."
    end

    respond_to do |format|
      format.turbo_stream do
        load_delivery_for_panel
        set_delivery_panel_data

        flash.now[:notice] = notice_msg

        render turbo_stream: [
          turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
          turbo_stream.update("modal", ""),
          turbo_stream.replace(
            dom_id(@delivery, :detail),
            partial: "deliveries/show_partials/detail_data",
            locals: {
              delivery: @delivery,
              future_deliveries: @future_deliveries,
              delivery_history: @delivery_history
            }
          )
        ]
      end
    end
  end

  def archive
    authorize @delivery, :edit?

    respond_to do |format|
      if @delivery.update(status: :archived)
        # 🔹 Registrar evento
        DeliveryEvent.record(
          delivery: @delivery,
          action: "archived",
          actor: current_user,
          payload: {archived_at: Time.current.to_s}
        )

        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove(dom_id(@delivery, :card)),
            turbo_stream.replace("delivery_detail", partial: "deliveries/shared_partials/detail_empty_state")
          ]
        end
        format.html { redirect_to deliveries_path, notice: "La entrega fue archivada correctamente." }
      else
        format.turbo_stream do
          load_delivery_for_panel
          set_delivery_panel_data
          render turbo_stream: turbo_stream.replace(
            dom_id(@delivery, :detail),
            partial: "deliveries/show_partials/detail_data",
            locals: {delivery: @delivery, future_deliveries: @future_deliveries, delivery_history: @delivery_history}
          )
        end
        format.html { redirect_to @delivery, alert: "No se pudo archivar la entrega." }
      end
    end
  end

  def confirm_all_items
    authorize @delivery, :edit?

    if @delivery.bulk_locked?
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Esta entrega no permite acciones masivas en su estado actual."
          render turbo_stream: turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
            status: :unprocessable_entity
        end
        format.html { redirect_to @delivery, alert: "Esta entrega no permite acciones masivas." }
      end
      return
    end

    items = @delivery.delivery_items.bulk_confirmable
    items.each { |item| item.update!(status: :confirmed) }

    @delivery.mark_as_confirmed_by_vendor!
    @delivery.reload.update_status_based_on_items
    @delivery.reload

    # 🔹 Registrar evento
    DeliveryEvent.record(
      delivery: @delivery,
      action: "items_bulk_confirmed",
      actor: current_user,
      payload: {
        items_count: items.count,
        item_ids: items.map(&:id),
        products: items.map { |i| i.order_item&.product }.compact
      }
    )

    respond_to do |format|
      format.turbo_stream do
        render_delivery_update_stream(
          notice: "#{items.count} producto(s) confirmado(s) para entrega.",
          include_product_table: true
        )
      end
      format.html { redirect_to delivery_path(@delivery), notice: "Producto(s) confirmado(s) para entrega." }
    end
  end

  # Variante de #index filtrada a una semana ISO (params[:week]/[:year]),
  # reusando la vista deliveries/index.
  def by_week
    authorize Delivery, :index?
    @sellers = Seller.order(:name)
    session[:deliveries_return_to] = request.fullpath
    @week = (1..53).cover?(params[:week].to_i) ? params[:week].to_i : Date.current.cweek
    @year = (params[:year].to_i >= 2000) ? params[:year].to_i : Date.current.cwyear
    start_date = Date.commercial(@year, @week, 1)
    scope = Delivery.for_week(start_date).includes(order: :client, delivery_address: {}, delivery_items: {})
    @q = scope.ransack(params[:q])
    @deliveries = @q.result.order("deliveries.delivery_date ASC").page(params[:page])
    render :index
  end

  # Variante de #index filtrada a entregas con delivery_items marcados
  # service_case, reusando la vista deliveries/index.
  def service_cases
    authorize Delivery, :index?
    @sellers = Seller.order(:name)
    session[:deliveries_return_to] = request.fullpath
    scope = Delivery.joins(order: :client).merge(Delivery.with_service_cases).includes(:order, :delivery_address, :delivery_items)
    @q = scope.ransack(params[:q])
    @deliveries = @q.result.order("deliveries.delivery_date ASC, clients.name ASC").page(params[:page])
    render :index
  end

  def addresses_for_client
    authorize Delivery, :addresses_for_client?
    client = Client.find(params[:client_id])
    render json: client.delivery_addresses.select(:id, :address, :description, :latitude, :longitude, :plus_code)
  end

  def orders_for_client
    authorize Delivery, :orders_for_client?
    client = Client.find(params[:client_id])
    orders = client.orders.select(:id, :number).order(created_at: :desc)
    render json: orders.map { |o| {id: o.id, number: o.number, text: o.number} }
  end

  def note
    authorize @delivery, :edit?
    render partial: "delivery_items/form_note", locals: {delivery: @delivery}
  end

  def unconfirm
    authorize @delivery, :edit?

    if @delivery.bulk_locked?
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "No se puede desconfirmar una entrega en estado #{@delivery.display_status}."
          render turbo_stream: turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
            status: :unprocessable_entity
        end
        format.html { redirect_to @delivery, alert: "No se puede desconfirmar esta entrega." }
      end
      return
    end

    @delivery.unconfirm!
    @delivery.reload

    DeliveryEvent.record(
      delivery: @delivery,
      action: "unconfirmed",
      actor: current_user,
      payload: {unconfirmed_at: Time.current.to_s}
    )

    respond_to do |format|
      format.turbo_stream do
        render_delivery_update_stream(
          notice: "Entrega desconfirmada. Los productos volvieron a estado pendiente.",
          include_product_table: true
        )
      end
      format.html { redirect_to @delivery, notice: "Entrega desconfirmada correctamente." }
    end
  rescue => e
    render_delivery_error_flash("Error al desconfirmar: #{e.message}")
  end

  def update_status
    authorize @delivery, :edit?
    @delivery.update_status_based_on_items
    redirect_to @delivery, notice: "El estado de la entrega ha sido actualizado."
  end

  def take_order
    authorize @delivery, :take_order?
    @delivery.order.take_by_user!(current_user)
    redirect_to @delivery,
      notice: "Tomaste el pedido #{@delivery.order.number}. Ahora está asignado a ti."
  rescue => e
    redirect_to @delivery, alert: "No se pudo tomar el pedido: #{e.message}"
  end

  def reopen
    authorize @delivery, :reopen?

    unless @delivery.reopenable?
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Esta entrega no puede reabrirse desde su estado actual (#{@delivery.display_status})."
          render turbo_stream: turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
            status: :unprocessable_entity
        end
        format.html { redirect_to @delivery, alert: "Esta entrega no puede reabrirse." }
      end
      return
    end

    previous_status = @delivery.status
    @delivery.reopen!

    DeliveryEvent.record(
      delivery: @delivery,
      action: "reopened",
      actor: current_user,
      payload: {
        previous_status: previous_status,
        reopened_at: Time.current.to_s
      }
    )

    respond_to do |format|
      format.turbo_stream do
        load_delivery_for_panel
        set_delivery_panel_data

        flash.now[:notice] = "Entrega reabierta. Volvió a estado 'Pendiente de confirmar'."

        render turbo_stream: [
          turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
          turbo_stream.update(
            "delivery_detail",
            partial: "deliveries/show_partials/detail_data",
            locals: {
              delivery: @delivery,
              future_deliveries: @future_deliveries,
              delivery_history: @delivery_history
            }
          ),
          turbo_stream.replace(
            dom_id(@delivery, :card),
            partial: "deliveries/index_partials/delivery_card",
            locals: {delivery: @delivery}
          )
        ]
      end
      format.html { redirect_to @delivery, notice: "Entrega reabierta correctamente." }
    end
  rescue => e
    render_delivery_error_flash("Error al reabrir la entrega: #{e.message}")
  end

  private

  def set_delivery
    @delivery = Delivery.includes(
      order: [:client, :seller, :order_contacts],
      delivery_address: :client,
      delivery_items: [:delivery_item_notes, {order_item: :order}]
    ).find(params[:id])
  end

  def load_delivery_for_panel
    @delivery = Delivery.includes(
      :order,
      :delivery_address,
      delivery_items: [:delivery_item_notes, {order_item: :order}],
      order: [:client, :seller, :order_contacts],
      delivery_address: :client,
      delivery_plan_assignment: {delivery_plan: :driver}
    ).find(@delivery.id)
  end

  def set_delivery_panel_data
    @future_deliveries = Delivery
      .includes(order: :client, delivery_address: :client)
      .where(order_id: @delivery.order_id, delivery_address_id: @delivery.delivery_address_id)
      .where.not(id: @delivery.id)
      .where(status: [:scheduled, :ready_to_deliver, :in_plan, :in_route])

    @delivery_history = @delivery.order.deliveries
      .includes(
        delivery_items: [:delivery_item_notes, {order_item: :order}],
        delivery_address: :client
      )
      .where(delivery_address_id: @delivery.delivery_address_id)
      .order(:delivery_date)
  end

  def set_addresses
    @addresses = @delivery&.order&.client&.delivery_addresses&.to_a || []
  end

  # Compartido por las acciones que, tras actualizar @delivery, refrescan el
  # panel de detalle + la tarjeta del índice vía turbo_stream (update,
  # mark_as_delivered, start/end_warehousing, confirm_all_items, unconfirm).
  # `extra_streams` va ANTES del stream de detalle (ej. cerrar un modal);
  # `include_product_table` agrega el refresco de la tabla de productos
  # entre el detalle y la tarjeta, para las acciones que tocan delivery_items.
  def render_delivery_update_stream(notice:, extra_streams: [], include_product_table: false)
    load_delivery_for_panel
    set_delivery_panel_data
    flash.now[:notice] = notice

    streams = [turbo_stream.replace("flash_messages", partial: "layouts/flashes")]
    streams.concat(extra_streams)
    streams << turbo_stream.replace(
      dom_id(@delivery, :detail),
      partial: "deliveries/show_partials/detail_data",
      locals: {delivery: @delivery, future_deliveries: @future_deliveries, delivery_history: @delivery_history}
    )
    if include_product_table
      streams << turbo_stream.replace(
        "delivery_items_list",
        partial: "deliveries/show_partials/product_table",
        locals: {delivery: @delivery}
      )
    end
    streams << turbo_stream.replace(
      dom_id(@delivery, :card),
      partial: "deliveries/index_partials/delivery_card",
      locals: {delivery: @delivery}
    )

    render turbo_stream: streams
  end

  def render_delivery_error_flash(message)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message
        render turbo_stream: turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
          status: :unprocessable_entity
      end
      format.html { redirect_to @delivery, alert: message }
    end
  end

  def sanitize_delivery_address_param!
    raw = params.dig(:delivery, :delivery_address_id).to_s
    params[:delivery][:delivery_address_id] = nil if raw == "__new__" || raw.blank?
  rescue
    nil
  end

  def sanitize_order_id_param!
    raw = params.dig(:delivery, :order_id).to_s
    params[:delivery][:order_id] = nil if raw == "__new__" || raw.blank?
  rescue
    nil
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

  def handle_sala_pickup_error(e)
    Rails.logger.error "❌ Error sala pickup: #{e.message}"

    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = "Error al registrar retiro en sala: #{e.message}"
        render turbo_stream: turbo_stream.replace(
          "flash_messages",
          partial: "layouts/flashes"
        ), status: :unprocessable_entity
      end
      format.html do
        redirect_to delivery_path(@delivery), alert: "Error al registrar retiro en sala: #{e.message}"
      end
    end
  end

  def handle_create_error(e)
    Rails.logger.error "Error crear entrega: #{e.message}"
    @delivery ||= Delivery.new
    if (permitted = delivery_rerender_params)
      @delivery.assign_attributes(permitted.except(:_return_to_panel))
    end

    @client = find_or_initialize_client_from_params
    @order = find_or_initialize_order_from_params(@client)
    @addresses = @client.persisted? ? @client.delivery_addresses.to_a : []
    @orders = @client.persisted? ? @client.orders.to_a : []
    @clients = Client.all.order(:name)

    flash.now[:alert] = "Error al crear la entrega: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  def handle_update_error(e)
    if (permitted = delivery_rerender_params)
      @delivery.assign_attributes(permitted.except(:_return_to_panel))
    end

    @order = @delivery.order
    @client = @order.client
    @addresses = @client.delivery_addresses.order(:description).to_a
    @orders = @client.orders.to_a
    @clients = [@client]

    flash.now[:alert] = "Error al actualizar la entrega: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  # Permit list compartida por handle_create_error/handle_update_error para
  # re-renderizar el formulario tras un fallo. Reusa los sanitizadores de
  # "__new__" ya existentes (sanitize_delivery_address_param!/
  # sanitize_order_id_param!) en vez de reimplementarlos sobre el hash ya
  # permitido.
  def delivery_rerender_params
    return nil unless params[:delivery].present?

    sanitize_delivery_address_param!
    sanitize_order_id_param!

    params.require(:delivery).permit(
      :delivery_date, :delivery_address_id, :order_id,
      :contact_name, :contact_phone, :delivery_notes, :delivery_type, :delivery_time_preference,
      :condominio_number, :casa_number, :_return_to_panel,
      delivery_items_attributes: [
        :id, :order_item_id, :quantity_delivered, :service_case, :status, :notes, :_destroy,
        {order_item_attributes: [:id, :product, :quantity, :notes]}
      ]
    )
  end

  def register_delivery_note(default_note:, event_action:, event_context:)
    note = params.dig(:delivery, :delivery_notes).presence || default_note
    existing = @delivery.delivery_notes.to_s.strip
    new_notes = existing.present? ? "#{existing}\n#{note}" : note
    @delivery.update!(delivery_notes: new_notes)
    DeliveryEvent.record(
      delivery: @delivery,
      action: event_action,
      actor: current_user,
      payload: { context: event_context, note: note }
    )
  end

  def register_devolucion_note
    register_delivery_note(
      default_note: "#{Deliveries::Vocabulary.service_type_label("devolucion")} al cliente",
      event_action: "service_case_noted",
      event_context: "devolucion"
    )
  end

  def register_reparacion_note
    register_delivery_note(
      default_note: Deliveries::Vocabulary.service_type_label("reparacion"),
      event_action: "service_case_noted",
      event_context: "reparacion"
    )
  end

  def register_repair_entrega_note
    register_delivery_note(
      default_note: "Entrega de producto reparado al cliente",
      event_action: "repair_service_noted",
      event_context: "repair_entrega"
    )
  end

  def handle_service_case_error(e)
    @delivery ||= Delivery.new
    @delivery.delivery_type ||= params.dig(:delivery, :delivery_type) || :pickup
    @delivery.status ||= :scheduled

    if params[:delivery].present?
      sanitize_delivery_address_param!
      sanitize_order_id_param!

      permitted = params.require(:delivery).permit(
        :delivery_date, :delivery_address_id, :order_id,
        :contact_name, :contact_phone, :delivery_notes, :delivery_type, :delivery_time_preference,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :status, :notes, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
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
      sanitize_delivery_address_param!

      permitted = params.require(:delivery).permit(
        :delivery_date, :delivery_type, :delivery_address_id,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
      @service_case.assign_attributes(permitted)

      if @service_case.delivery_type.is_a?(String)
        @service_case.delivery_type = @service_case.delivery_type.to_sym
      end
      if (dd = params.dig(:delivery, :delivery_date)).present?
        @service_case.delivery_date = parse_date(dd) || @service_case.delivery_date
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

  def handle_repair_service_error(e)
    @delivery ||= Delivery.new(delivery_type: :repair_pickup, status: :scheduled)

    if params[:delivery].present?
      sanitize_delivery_address_param!
      sanitize_order_id_param!

      permitted = params.require(:delivery).permit(
        :delivery_date, :delivery_address_id, :order_id,
        :contact_name, :contact_phone, :delivery_notes, :delivery_type, :delivery_time_preference,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :status, :notes, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
      # "repair_with_return" es un valor de despacho del formulario, no un delivery_type real.
      permitted.delete(:delivery_type) unless Delivery.delivery_types.key?(permitted[:delivery_type].to_s)
      @delivery.assign_attributes(permitted)
    end

    @client = if params[:client_id].present?
      Client.find_by(id: params[:client_id])
    elsif params[:client].present?
      Client.new(params.require(:client).permit(:name, :phone, :email))
    else
      @delivery.order&.client || Client.new
    end

    @clients = Client.all.order(:name)
    @addresses = @client.present? ? @client.delivery_addresses.to_a : []

    flash.now[:alert] = "Error al crear el servicio de reparación: #{e.message}"
    render :new_repair_service, status: :unprocessable_entity
  end

  def handle_repair_service_existing_error(e, parent_delivery)
    Rails.logger.error("Error RepairServiceExisting: #{e.message}")
    @delivery = parent_delivery

    @repair_delivery ||= Delivery.new(
      order: parent_delivery.order,
      delivery_address: parent_delivery.delivery_address,
      delivery_type: :repair_pickup,
      delivery_date: Date.current
    )

    @addresses = parent_delivery.order.client.delivery_addresses.to_a

    if @repair_delivery.delivery_items.blank?
      parent_delivery.order.order_items.each do |oi|
        @repair_delivery.delivery_items.build(
          order_item: oi,
          quantity_delivered: oi.quantity,
          status: :pending
        )
      end
    end

    flash.now[:alert] = "Error al generar servicio de reparación: #{e.message}"
    render :new_repair_service_for_existing, status: :unprocessable_entity
  end

  def handle_internal_error(e)
    Rails.logger.error "Error crear mandado interno: #{e.message}"
    @delivery ||= Delivery.new(delivery_type: :internal_delivery, status: :scheduled, delivery_date: Date.current)
    @delivery.delivery_items.build.build_order_item if @delivery.delivery_items.empty?
    flash.now[:alert] = "Error al crear el mandado interno: #{e.message}"
    render :new_internal_delivery, status: :unprocessable_entity
  end
end
