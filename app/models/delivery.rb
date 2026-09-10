# Una entrega (o retiro/servicio) sobre una dirección, perteneciente a un
# {Order}. Agrupa {DeliveryItem}s; su status es derivado del status agregado
# de esos items (ver {#calculate_delivery_status}) salvo en estados que
# "congelan" el recálculo (archived, warehousing). Puede pertenecer a un
# {DeliveryPlan} (a través de delivery_plan_assignment) y a un
# {DeliveryGroup} (entregas relacionadas que se gestionan juntas).
class Delivery < ApplicationRecord
  include ActionView::RecordIdentifier
  include HasDisplayStatus

  DISPLAY_STATUS_LABELS = {
    "scheduled" => "Pendiente de confirmar",
    "ready_to_deliver" => "Confirmada para entregar",
    "in_plan" => "En plan",
    "in_route" => "En ruta",
    "delivered" => "Entregada",
    "rescheduled" => "Reprogramada",
    "cancelled" => "Cancelada",
    "archived" => "Archivada",
    "failed" => "Entrega fracasada",
    "loaded_on_truck" => "Cargada en camión",
    "warehousing" => "En bodegaje"
  }.freeze

  has_paper_trail
  belongs_to :order
  belongs_to :delivery_address
  belongs_to :source_showroom,      class_name: "Showroom", optional: true
  belongs_to :destination_showroom, class_name: "Showroom", optional: true
  has_many :delivery_items, dependent: :destroy
  has_many :order_items, through: :delivery_items
  has_one :delivery_plan_assignment, dependent: :destroy
  has_one :delivery_plan, through: :delivery_plan_assignment
  has_many :delivery_events, dependent: :destroy
  has_one :delivery_group_membership, dependent: :destroy
  has_one :delivery_group, through: :delivery_group_membership

  accepts_nested_attributes_for :delivery_items, allow_destroy: true

  before_validation :generate_tracking_token, on: :create
  after_create_commit -> { broadcast_refresh_to("deliveries") }
  after_update_commit :broadcast_delivery_updates

  delegate :latitude, :longitude, :address, :plus_code, to: :delivery_address, allow_nil: true
  delegate :client, to: :delivery_address, allow_nil: true

  # @return [Hash{Symbol => Float}] coordenadas de la dirección de entrega
  def location
    {lat: latitude.to_f, lng: longitude.to_f}
  end

  # @return [String, nil] URL pública de tracking (nil si no hay token)
  def public_tracking_url
    return nil if tracking_token.blank?
    Rails.application.routes.url_helpers.public_tracking_url(token: tracking_token)
  end

  # ============================================================================
  # ENUMS
  # ============================================================================

  enum :status, {
    scheduled: 0,
    ready_to_deliver: 1,
    in_plan: 2,
    in_route: 3,
    delivered: 4,
    rescheduled: 5,
    cancelled: 6,
    archived: 7,
    failed: 8,
    loaded_on_truck: 9,
    warehousing: 10
  }

  enum :delivery_type, {
    normal: 0,
    pickup_with_return: 1,
    return_delivery: 2,
    onsite_repair: 3,
    internal_delivery: 4,
    only_pickup: 5,
    showroom: 6,
    repair_pickup: 7,
    repair_return: 8
  }

  enum :load_status, {
    empty: 0,
    partial: 1,
    all_loaded: 2,
    some_missing: 3
  }, prefix: :load

  # ============================================================================
  # CONSTANTES
  # ============================================================================

  SERVICE_CASE_TYPES = %w[pickup_with_return return_delivery onsite_repair only_pickup].freeze
  REPAIR_SERVICE_TYPES = %w[repair_pickup repair_return].freeze
  BULK_LOCKED_STATUSES = %w[delivered rescheduled cancelled archived failed warehousing].freeze
  REOPENABLE_STATUSES = %w[delivered cancelled archived].freeze
  HIDDEN_FROM_ROUTE_MAP_STATUSES = %w[cancelled rescheduled archived].freeze

  # Estados que cualquier rol (no solo admin) puede ver al mirar un plan ya
  # armado (tabla de paradas, tarjetas, Excel). cancelled/archived/rescheduled/
  # failed/warehousing quedan afuera para todos salvo admin — ver una entrega
  # cancelada ahí genera confusión en logística/vendedores.
  VISIBLE_TO_ALL_STATUSES = %w[scheduled ready_to_deliver in_plan in_route delivered loaded_on_truck].freeze

  # Estados terminales de items — no participan en el flujo activo
  ITEM_TERMINAL_STATUSES = %w[delivered cancelled rescheduled failed].freeze
  # Estados activos de items — determinan el estado de la entrega
  ITEM_ACTIVE_STATUSES = %w[pending confirmed in_plan in_route loaded_on_truck warehousing].freeze

  # Status que debe tomar un DeliveryItem nuevo (o reactivado) según el nivel
  # actual de la entrega, para no "atrasar" una entrega que ya avanzó (ver
  # calculate_delivery_status: el estado activo menos avanzado manda).
  DELIVERY_STATUS_TO_ITEM_STATUS = {
    "scheduled" => "pending",
    "ready_to_deliver" => "confirmed",
    "in_plan" => "in_plan",
    "loaded_on_truck" => "loaded_on_truck",
    "warehousing" => "warehousing",
    "in_route" => "in_route"
  }.freeze

  # ============================================================================
  # VALIDACIONES
  # ============================================================================

  validates :delivery_date, presence: true

  # ============================================================================
  # SCOPES
  # ============================================================================

  scope :service_cases, -> { where(delivery_type: SERVICE_CASE_TYPES) }
  scope :repair_services, -> { where(delivery_type: REPAIR_SERVICE_TYPES) }
  scope :normal_deliveries, -> { where(delivery_type: :normal) }
  scope :pending, -> { where(status: [:scheduled, :ready_to_deliver, :in_route]) }
  scope :overdue, -> {
    where("delivery_date < ?", Date.current)
      .where.not(status: [statuses[:delivered], statuses[:rescheduled], statuses[:cancelled], statuses[:loaded_on_truck]])
  }
  scope :eligible_for_plan, -> {
    where.not(status: [:delivered, :cancelled, :rescheduled, :in_plan, :in_route, :archived, :failed, :loaded_on_truck, :warehousing])
  }
  scope :not_assigned_to_plan, -> { where.not(id: DeliveryPlanAssignment.select(:delivery_id)) }
  scope :available_for_plan, -> { eligible_for_plan.not_assigned_to_plan }
  scope :rescheduled_this_week, -> {
    where(status: :rescheduled, delivery_date: Date.current.beginning_of_week..Date.current.end_of_week)
  }
  scope :overdue_unplanned, -> {
    where("delivery_date < ?", Date.current)
      .eligible_for_plan
      .not_assigned_to_plan
  }
  # @param date [Date] cualquier día dentro de la semana ISO deseada
  scope :for_week, ->(date) { where(delivery_date: date.beginning_of_week..date.end_of_week) }
  scope :with_service_cases, -> {
    joins(:delivery_items).where(delivery_items: {service_case: true}).distinct
  }
  scope :warehousing_expiring_soon, -> {
    where(status: :warehousing)
      .where(warehousing_until: Date.current..(Date.current + 8.days))
  }

  # ============================================================================
  # BULK ACTIONS
  # ============================================================================

  # @return [Boolean] true si el status actual bloquea acciones masivas (bulk actions)
  def bulk_locked?
    status.in?(BULK_LOCKED_STATUSES)
  end

  # @return [Boolean] true si la entrega puede reabrirse con {#reopen!}
  def reopenable?
    status.in?(REOPENABLE_STATUSES)
  end

  # Una entrega cancelada, reagendada o archivada ya no debe verse como
  # parada en el mapa de la ruta (el DeliveryPlanAssignment no se destruye
  # cuando cambia el status del delivery, así que hay que filtrarla aquí).
  #
  # @return [Boolean]
  def hidden_from_route_map?
    status.in?(HIDDEN_FROM_ROUTE_MAP_STATUSES)
  end

  # Admin ve toda entrega en un plan ya armado (marcada con su estado real);
  # cualquier otro rol solo ve las que están en un estado "normal" del flujo.
  #
  # @param user [User, nil]
  # @return [Boolean]
  def visible_in_plan_for?(user)
    user&.admin? || status.in?(VISIBLE_TO_ALL_STATUSES)
  end

  # Reabre una entrega bloqueada (delivered/cancelled/archived): vuelve la
  # entrega y todos sus items a su estado inicial (scheduled/pending).
  #
  # @return [void]
  def reopen!
    transaction do
      delivery_items.find_each do |item|
        item.update!(status: :pending, load_status: :unloaded)
      end
      update!(
        status: :scheduled,
        load_status: :empty,
        confirmed_by_vendor: false,
        confirmed_by_vendor_at: nil
      )
    end
  end

  # ============================================================================
  # RANSACK
  # ============================================================================

  ransacker :status, formatter: proc { |v| statuses[v] } do |parent|
    parent.table[:status]
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[delivery_date status delivery_type contact_name contact_phone delivery_notes delivery_time_preference reschedule_reason condominio_number casa_number]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[order delivery_address delivery_items]
  end

  # Filtra `scope` a las entregas donde el predicate de instancia (ej.
  # :requires_service_case_action?, :requires_repair_service_action?) da
  # true. Esos predicates dependen de keywords dinámicos y normalización de
  # texto (ver Deliveries::ServiceCaseDetector/RepairServiceDetector) que no
  # es practicable expresar en SQL, así que hay que cargar y evaluar en
  # memoria — esto al menos evita repetir ese "select → ids → where(id:)"
  # en cada controller que necesita filtrar por uno de estos predicates.
  #
  # @param scope [ActiveRecord::Relation<Delivery>]
  # @param predicate [Symbol] nombre de un predicate de instancia (ej. :requires_service_case_action?)
  # @return [ActiveRecord::Relation<Delivery>]
  def self.filter_by_predicate(scope, predicate)
    ids = scope.includes(delivery_items: :order_item).select { |d| d.public_send(predicate) }.map(&:id)
    scope.where(id: ids)
  end

  # ============================================================================
  # MÉTODOS PÚBLICOS
  # ============================================================================

  # @return [Boolean] true si está en bodegaje y vence en 8 días o menos
  def warehousing_expiring_soon?
    warehousing? && warehousing_until.present? && warehousing_until <= Date.current + 8.days
  end

  # @return [Integer, nil] días restantes de bodegaje, o nil si no aplica
  def warehousing_days_remaining
    return nil unless warehousing? && warehousing_until.present?
    (warehousing_until - Date.current).to_i
  end

  # Pone la entrega en bodegaje hasta la fecha dada.
  #
  # @param until_date [Date]
  # @return [void]
  def start_warehousing!(until_date)
    update!(status: :warehousing, warehousing_until: until_date)
  end

  # Saca la entrega de bodegaje, volviendo a "scheduled".
  #
  # @return [void]
  def end_warehousing!
    update!(status: :scheduled, warehousing_until: nil)
  end

  # @return [String]
  def client_name
    order.client.name
  end

  # @return [String]
  def order_number
    order.number
  end

  # @return [Boolean] true si el delivery_type es uno de los "caso de servicio"
  def service_case?
    delivery_type.in?(SERVICE_CASE_TYPES)
  end

  # @return [Boolean] true si el delivery_type es uno de "servicio de reparación"
  def repair_service?
    delivery_type.in?(REPAIR_SERVICE_TYPES)
  end

  # @return [String] etiqueta legible del delivery_type
  def display_type
    case delivery_type
    when "normal" then "Entrega normal"
    when "pickup_with_return" then "Retiro del producto en sala y entrega posterior al cliente"
    when "return_delivery" then "#{Deliveries::Vocabulary.service_type_label("devolucion")} de producto"
    when "onsite_repair" then Deliveries::Vocabulary.service_type_label("reparacion")
    when "only_pickup" then "Solo retiro del producto (sin entrega posterior)"
    when "internal_delivery" then "Mandado Interno"
    when "showroom" then "Movimiento de Showroom"
    when "repair_pickup" then "Servicio de Reparación — #{Deliveries::Vocabulary.service_type_label("recoleccion")}"
    when "repair_return" then "Servicio de Reparación — #{Deliveries::Vocabulary.service_type_label("devolucion")}"
    else delivery_type.to_s.humanize
    end
  end

  # Recalcula `load_status` en base al load_status de los delivery_items
  # (empty/partial/all_loaded/some_missing). Si todos quedan cargados,
  # además avanza el status de la entrega a :loaded_on_truck.
  #
  # @return [void]
  def recalculate_load_status!
    items = delivery_items.reload
    return if items.empty?

    loaded_count = items.load_loaded.count
    missing_count = items.load_missing.count
    total_count = items.count

    new_load_status = if missing_count > 0
      :some_missing
    elsif loaded_count == total_count
      :all_loaded
    elsif loaded_count > 0
      :partial
    else
      :empty
    end

    if new_load_status == :all_loaded
      update(load_status: new_load_status, status: :loaded_on_truck)
    else
      update(load_status: new_load_status)
    end
  end

  # Marca como cargados todos los items accionables en bulk (excepto los
  # marcados missing) y recalcula load_status/status de la entrega.
  #
  # @return [void]
  def mark_all_loaded!
    transaction do
      delivery_items
        .bulk_actionable
        .where.not(load_status: DeliveryItem.load_statuses[:missing])
        .find_each do |item|
          item.update!(load_status: :loaded, status: :loaded_on_truck)
        end

      recalculate_load_status!
      update_status_based_on_items
    end
  end

  # @return [Boolean] true si {Deliveries::ErrorDetector} reporta un error de dirección
  def address_error?
    Deliveries::ErrorDetector.new(self).errors.any? { |e| e[:category] == "Dirección" }
  end

  # Vuelve todos los items a load_status :unloaded y recalcula.
  #
  # @return [void]
  def reset_load_status!
    transaction do
      delivery_items.find_each do |item|
        item.update!(load_status: :unloaded)
      end

      recalculate_load_status!
    end
  end

  # @return [String] etiqueta legible del load_status
  def display_load_status
    case load_status
    when "empty" then "Sin cargar"
    when "partial" then "Parcialmente cargado"
    when "all_loaded" then "Completamente cargado"
    when "some_missing" then "Con faltantes"
    else load_status.to_s.humanize
    end
  end

  # @return [Integer] porcentaje (0-100) de items con load_status :loaded
  def load_percentage
    total = delivery_items.count
    return 0 if total.zero?
    loaded = delivery_items.load_loaded.count
    ((loaded.to_f / total) * 100).round
  end

  # @return [Array<DeliveryItem>] items pendientes de retiro en sala (memoized)
  def sala_pickup_items
    @sala_pickup_items ||= Deliveries::SalaPickupDetector.new(self).actionable_items
  end

  # @return [Hash] items pendientes de retiro agrupados por sala (memoized)
  def items_by_sala
    @items_by_sala ||= Deliveries::SalaPickupDetector.new(self).items_by_sala
  end

  # @return [Array<DeliveryItem>] items que requieren acción de caso de servicio (memoized)
  def service_case_items
    @service_case_items ||= Deliveries::ServiceCaseDetector.new(self).actionable_items
  end

  # @return [Boolean]
  def requires_service_case_action?
    service_case_items.any?
  end

  # @return [Array<DeliveryItem>] items que requieren acción de servicio de reparación (memoized)
  def repair_service_items
    @repair_service_items ||= Deliveries::RepairServiceDetector.new(self).actionable_items
  end

  # @return [Boolean]
  def requires_repair_service_action?
    repair_service_items.any?
  end

  # @return [Boolean]
  def requires_sala_pickup?
    sala_pickup_items.any?
  end

  # ============================================================================
  # RECÁLCULO DE ESTADO BASADO EN ITEMS
  # ============================================================================

  # Status que debe recibir un DeliveryItem nuevo (o reactivado) sobre esta
  # entrega: el nivel al que ya llegó la entrega, no siempre "pending".
  # Evita que agregar un producto a una entrega en in_plan/ready_to_deliver/
  # in_route/etc. la retroceda a "Pendiente de confirmar".
  # @return [String] status que debe recibir un item nuevo/reactivado
  def default_item_status
    DELIVERY_STATUS_TO_ITEM_STATUS.fetch(status, "pending")
  end

  # Punto de entrada principal. Siempre refleja el estado real de los items.
  # No bloquea por estado actual de la entrega (excepto archived/warehousing).
  #
  # @return [void]
  def update_status_based_on_items
    return if archived? || warehousing?

    item_statuses = delivery_items.reload.map(&:status)
    return if item_statuses.empty?

    new_status = calculate_delivery_status(item_statuses)
    return if new_status.blank? || new_status.to_s == status.to_s

    if new_status == :ready_to_deliver && !confirmed_by_vendor?
      update!(status: new_status, confirmed_by_vendor: true, confirmed_by_vendor_at: Time.current)
    else
      update!(status: new_status)
    end
  end

  # @return [ActiveRecord::Relation<DeliveryItem>] items elegibles para armar un plan nuevo
  def active_items_for_plan
    delivery_items.eligible_for_plan
  end

  # @param user [User, nil]
  # @return [ActiveRecord::Relation<DeliveryItem>]
  def active_items_for_plan_for(user)
    delivery_items.merge(DeliveryItem.eligible_for_plan_for(user))
  end

  # Items to show when viewing an ALREADY-ASSIGNED plan (not when building a
  # new one). Sin user (o user no-admin): solo los 6 estados "normales" del
  # flujo — cancelado/reagendado/archivado/fallido/bodegaje se ocultan del
  # todo, generan confusión en logística/vendedores. Admin ve todo.
  #
  # @param user [User, nil]
  # @return [ActiveRecord::Relation<DeliveryItem>]
  def items_visible_in_plan(user = nil)
    return delivery_items if user&.admin?
    delivery_items.merge(DeliveryItem.eligible_for_plan_for_others)
  end

  # @return [Integer] suma de `quantity_delivered` entre todos los delivery_items
  def total_items
    delivery_items.sum(:quantity_delivered)
  end

  # Marca como entregados todos los items en estados activos y avanza el
  # status de la entrega a :delivered si todos quedaron entregados.
  #
  # @return [void]
  def mark_as_delivered!
    transaction do
      delivery_items
        .where(status: %i[pending confirmed in_plan in_route loaded_on_truck])
        .find_each(&:mark_as_delivered!)

      reload

      # Forzar delivered si todos los items lo están
      if delivery_items.reload.where.not(status: :delivered).none?
        update!(status: :delivered)
      else
        update_status_based_on_items
      end
    end
  end

  # @return [Boolean] true si todos los order_items asociados están "ready"
  def confirmed?
    order_items.all? { |oi| oi.status == "ready" }
  end

  # @return [Delivery, nil] próxima entrega (id mayor, no cancelled/archived) del mismo pedido
  def next_rescheduled_delivery
    order.deliveries
      .where("id > ?", id)
      .where.not(status: [:cancelled, :archived])
      .order(:id)
      .first
  end

  # @return [ActiveRecord::Relation<Delivery>] historial de entregas del mismo pedido y dirección
  def delivery_history
    order.deliveries
      .where(delivery_address_id: delivery_address_id)
      .includes(delivery_items: :order_item)
      .order(:delivery_date)
  end

  # Eventos de esta entrega + todas las entregas hermanas que comparten
  # al menos un order_item_id (misma dirección, mismo pedido).
  # Esto permite ver el ciclo completo de un ítem aunque haya cruzado
  # varias entregas (A→B→A de vuelta).
  # @param limit [Integer]
  # @return [ActiveRecord::Relation<DeliveryEvent>]
  def related_events(limit: 50)
    DeliveryEvent
      .where(delivery_id: sibling_delivery_ids)
      .includes(:actor, :delivery)
      .order(created_at: :desc)
      .limit(limit)
  end

  # @return [Integer]
  def related_events_count
    DeliveryEvent.where(delivery_id: sibling_delivery_ids).count
  end

  # @return [String]
  def status_humanize
    status.humanize
  end

  # @return [String]
  def delivery_type_humanize
    delivery_type.humanize
  end

  # ============================================================================
  # MÉTODOS DE CLASE
  # ============================================================================

  # @return [Array<Array(String, String)>] pares [etiqueta legible, valor de
  #   enum] para poblar un `<select>` de status
  def self.status_options_for_select
    statuses.keys.map { |s| [Delivery.new(status: s).display_status, s.to_s] }
  end

  # @param scope [ActiveRecord::Relation<Delivery>]
  # @return [String] CSV con una fila por delivery_item de las entregas del scope
  def self.to_csv(scope = all)
    CSV.generate(headers: true) do |csv|
      csv << ["Fecha de entrega", "Pedido", "Producto", "Cantidad", "Vendedor", "Cliente", "Dirección", "Estado", "Tipo"]
      scope.includes(order: [:client, :seller], delivery_address: :client, delivery_items: {order_item: :order}).find_each do |delivery|
        delivery.delivery_items.each do |di|
          csv << [
            delivery.delivery_date.strftime("%d/%m/%Y"),
            delivery.order.number,
            di.order_item.product,
            di.order_item.quantity,
            delivery.order.seller.seller_code,
            delivery.order.client.name,
            delivery.delivery_address.address,
            delivery.status_humanize,
            delivery.delivery_type_humanize
          ]
        end
      end
    end
  end

  # ============================================================================
  # CONFIRMACIÓN POR VENDEDOR
  # ============================================================================

  # Marca la entrega como confirmada por el vendedor.
  #
  # @param _user [User, nil] sin uso actualmente, reservado para auditoría futura
  # @return [void]
  def mark_as_confirmed_by_vendor!(_user = nil)
    update!(
      confirmed_by_vendor: true,
      confirmed_by_vendor_at: Time.current,
      status: :ready_to_deliver
    )
  end

  # Revierte la confirmación del vendedor (no-op si {#bulk_locked?}).
  #
  # @return [void]
  def unconfirm!
    return if bulk_locked?

    transaction do
      delivery_items.confirmed.find_each { |item| item.update!(status: :pending) }
      update!(confirmed_by_vendor: false, confirmed_by_vendor_at: nil)
      reload
      update_status_based_on_items
    end
  end

  # @return [ActiveRecord::Relation<Delivery>] otras entregas del mismo delivery_group
  def associated_deliveries
    return Delivery.none unless delivery_group
    delivery_group.deliveries.where.not(id: id)
  end

  private

  # IDs de todas las entregas (misma orden + dirección) que comparten al menos
  # un order_item con esta entrega. Incluye la entrega actual.
  # Siempre retorna al menos [id] para que la consulta funcione aunque no haya ítems.
  #
  # @return [Array<Integer>]
  def sibling_delivery_ids
    oi_ids = delivery_items.pluck(:order_item_id).uniq
    return [id] if oi_ids.empty?

    DeliveryItem
      .joins(:delivery)
      .where(
        order_item_id: oi_ids,
        deliveries: {order_id: order_id, delivery_address_id: delivery_address_id}
      )
      .distinct
      .pluck(:delivery_id)
  end

  # ============================================================================
  # CÁLCULO DE ESTADO — lógica centralizada
  # ============================================================================
  #
  # Jerarquía de decisión:
  #   1. Todos los items en el mismo estado terminal → ese estado
  #   2. Todos terminales pero mezclados → (delivered = failed) > cancelled > rescheduled
  #   3. Hay items activos → flujo operativo: manda el MENOS avanzado presente
  #      (pending > confirmed/in_plan > loaded_on_truck/warehousing > in_route),
  #      hasta que TODOS los items activos superen ese escalón.
  #   4. Mezcla activos + terminales → se decide por los activos (los terminales son histórico)
  #
  # Nota sobre el punto 2: si algo se entregó, la entrega cumplió su propósito
  # aunque otro item se haya reagendado/cancelado/fallado por separado — por
  # eso "delivered"/"failed" tienen la prioridad más alta entre los terminales
  # mezclados, y "rescheduled" la más baja (solo se ve cuando el 100% de los
  # items están reagendados — eso ya lo resuelve el punto 1).
  #
  # Nota sobre el punto 3: es lo opuesto al punto 2 a propósito — en el flujo
  # operativo no queremos "esconder" un item que todavía no avanzó (ej. un
  # producto agregado tarde que sigue pending) detrás de otros que ya están
  # en_ruta. "warehousing" no se devuelve nunca como resultado (solo se entra
  # ahí vía start_warehousing!, que congela el recálculo) — se trata como
  # equivalente a loaded_on_truck para este cálculo.
  # @param raw_statuses [Array<String, Symbol>] statuses de los delivery_items actuales
  # @return [Symbol] status agregado que debería tener la entrega
  def calculate_delivery_status(raw_statuses)
    statuses = raw_statuses.map(&:to_s)

    # ── 1. Todos iguales ──────────────────────────────────────────────────────
    return :delivered if statuses.all? { |s| s == "delivered" }
    return :cancelled if statuses.all? { |s| s == "cancelled" }
    return :rescheduled if statuses.all? { |s| s == "rescheduled" }
    return :failed if statuses.all? { |s| s == "failed" }

    # ── 2. Todos terminales pero mezclados ────────────────────────────────────
    if statuses.all? { |s| ITEM_TERMINAL_STATUSES.include?(s) }
      return :delivered if statuses.any? { |s| s == "delivered" }
      return :failed if statuses.any? { |s| s == "failed" }
      return :cancelled if statuses.any? { |s| s == "cancelled" }
      return :rescheduled
    end

    # ── 3 & 4. Hay items activos — los terminales son solo histórico ──────────
    active = statuses.select { |s| ITEM_ACTIVE_STATUSES.include?(s) }

    # pending es el escalón más bajo: si queda alguno, la entrega no avanza
    return :scheduled if active.any? { |s| s == "pending" }

    # confirmado/en plan: si hay un delivery_plan real, ya está in_plan;
    # si no, apenas está confirmada para entregar
    if active.any? { |s| s == "confirmed" }
      return delivery_plan.present? ? :in_plan : :ready_to_deliver
    end
    return :in_plan if active.any? { |s| s == "in_plan" }

    # cargado en camión / en bodegaje (empatados, tratados como un solo escalón)
    return :loaded_on_truck if active.any? { |s| %w[loaded_on_truck warehousing].include?(s) }

    # solo queda in_route: el escalón más avanzado
    :in_route
  end

  # @return [void]
  def generate_tracking_token
    self.tracking_token ||= SecureRandom.urlsafe_base64(32)
  end

  # ============================================================================
  # TURBO STREAM BROADCASTING
  # ============================================================================

  # @return [void]
  def broadcast_delivery_updates
    broadcast_refresh_to("deliveries")

    # El stream es compartido por todos los viewers de esta entrega, sin
    # importar su rol, así que no podemos calcular la policy real por
    # usuario aquí (broadcast_replace_to no es request-scoped) — se
    # renderiza en modo "solo lectura" (sin botones de acción) para no
    # exponer acciones de admin a quien no las tiene. El siguiente render
    # normal de la página (controller, con policy real) restaura los
    # botones para quien sí tenga permiso.
    broadcast_replace_to(
      "delivery_#{id}_detail",
      target: "delivery_detail_header_#{id}",
      partial: "deliveries/show_partials/detail_header",
      locals: {
        delivery: self,
        can_edit: false,
        can_approve: false,
        can_reassign_seller: false,
        can_new_service_case: false,
        can_reopen: false,
        is_admin: false
      }
    )
  end
end
