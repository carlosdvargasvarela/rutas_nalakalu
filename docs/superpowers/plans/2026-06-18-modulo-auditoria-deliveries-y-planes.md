# Mejora del módulo de auditoría (Deliveries + Delivery Plans) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar a `DeliveryPlan`/`DeliveryPlanAssignment` la misma narrativa de negocio que ya existe para `Delivery` (vía un nuevo modelo `PlanEvent`), cerrar los huecos donde `update_column`/`update_all` dejaban transiciones de estado sin ningún rastro de auditoría, y unificar el timeline de auditoría para que una entrega y su plan se vean mutuamente.

**Architecture:** Modelo nuevo `PlanEvent` (tabla `plan_events`) paralelo a `DeliveryEvent`, compartiendo un concern `EventLog`. Callbacks de modelo (`after_create`/`after_update`/`after_destroy`) generan los eventos automáticamente. Un nuevo módulo `AuditActor` resuelve el actor vía `PaperTrail.request.whodunnit` en los puntos sin `current_user` explícito. El timeline (`TimelineEntry`/`TimelineGrouper`/`TimelineHelper`) se extiende para mezclar `PlanEvent` igual que ya mezcla `DeliveryEvent`+`PaperTrail::Version`.

**Tech Stack:** Rails 7.2, Minitest + fixtures, PaperTrail 16.0.0, Kaminari, Ransack, PostgreSQL.

## Global Constraints

- No se migra ni renombra la tabla `versions`/`delivery_events` existente.
- No se instrumenta `Order`/`OrderItem` más allá de lo que ya existe — `app/models/order_item.rb:56,58` queda intacto.
- No se agrega exportación a PDF/Excel ni endpoint API.
- Todo punto de instrumentación nuevo debe ser no bloqueante: si `PlanEvent.record`/`DeliveryEvent.record` falla, debe loguear y devolver `nil`, nunca relanzar ni tumbar la transacción de negocio.
- Spec de referencia: `docs/superpowers/specs/2026-06-18-modulo-auditoria-deliveries-y-planes-design.md`.
- Corrección sobre la spec: la spec asume `delivery.delivery_plan_assignments` (plural) para hallar los planes de una entrega; el modelo real usa `has_one :delivery_plan_assignment` (singular, ver `app/models/delivery.rb:11`). El plan de abajo usa la asociación singular real — el timeline bidireccional de una `Delivery` mostrará el plan **actual**, no el historial completo de planes pasados (esa relación no se conserva una vez que un `DeliveryPlanAssignment` se destruye).

---

### Task 1: Migración `plan_events`

**Files:**
- Create: `db/migrate/20260618200000_create_plan_events.rb`
- Modify: `db/schema.rb` (autogenerado por la migración)

**Interfaces:**
- Produces: tabla `plan_events` con columnas `delivery_plan_id:integer not null`, `action:string not null`, `actor_id:integer`, `payload:text`, `created_at:datetime not null`. Usada por todas las tareas siguientes.

- [ ] **Step 1: Escribir la migración**

```ruby
# db/migrate/20260618200000_create_plan_events.rb
class CreatePlanEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :plan_events do |t|
      t.integer :delivery_plan_id, null: false
      t.string :action, null: false
      t.integer :actor_id
      t.text :payload
      t.datetime :created_at, null: false
    end

    add_index :plan_events, :delivery_plan_id
    add_index :plan_events, :action
    add_index :plan_events, :actor_id
    add_index :plan_events, :created_at

    add_foreign_key :plan_events, :delivery_plans, on_delete: :cascade
    add_foreign_key :plan_events, :users, column: :actor_id, on_delete: :nullify
  end
end
```

- [ ] **Step 2: Correr la migración**

Run: `bin/rails db:migrate`
Expected: `== 20260618200000 CreatePlanEvents: migrated` y `db/schema.rb` actualizado con `create_table "plan_events"` y los `add_foreign_key "plan_events", ...` correspondientes.

- [ ] **Step 3: Confirmar que el esquema de test se sincroniza**

Run: `RAILS_ENV=test bin/rails db:test:prepare`
Expected: termina sin error (Rails también lo hace automáticamente al correr tests, vía `maintain_test_schema!` en `test_helper.rb`, pero lo corremos explícito para confirmar ahora).

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260618200000_create_plan_events.rb db/schema.rb
git commit -m "feat: agregar tabla plan_events para auditoría de delivery_plans"
```

---

### Task 2: Extraer el concern `EventLog` desde `DeliveryEvent` (refactor sin cambio de comportamiento)

**Files:**
- Create: `app/models/concerns/event_log.rb`
- Modify: `app/models/delivery_event.rb` (reemplazo completo)
- Test: `test/models/delivery_event_test.rb` (nuevo — hoy no existe ningún test para este modelo)

**Interfaces:**
- Produces: `EventLog` concern con `validates :action`, scopes `recent`/`for_action`/`by_actor`, `payload_data`, `label`/`color`/`icon`/`actor_name` (leen `self.class::ACTION_LABELS`/`ACTION_COLORS`/`ACTION_ICONS`), y `self.record_event(attrs)` (class method vía `class_methods do ... end`, hace `create!` con `created_at: Time.current`, rescata cualquier error logueando y devuelve `nil`).
- Consumes: nada nuevo (ningún otro task previo).

- [ ] **Step 1: Escribir el test que fija el comportamiento actual de `DeliveryEvent` (debe pasar antes y después del refactor)**

```ruby
# test/models/delivery_event_test.rb
require "test_helper"

class DeliveryEventTest < ActiveSupport::TestCase
  test "record creates an event with the given action, actor and payload" do
    event = DeliveryEvent.record(
      delivery: deliveries(:one),
      action: "approved",
      actor: users(:one),
      payload: {note: "ok"}
    )

    assert event.persisted?
    assert_equal "approved", event.action
    assert_equal users(:one).id, event.actor_id
    assert_equal({"note" => "ok"}, event.payload_data)
  end

  test "record returns nil and does not raise when creation fails" do
    result = DeliveryEvent.record(delivery: nil, action: "approved")

    assert_nil result
  end

  test "label falls back to humanized action for unknown actions" do
    event = DeliveryEvent.new(action: "some_unmapped_action")

    assert_equal "Some unmapped action", event.label
  end

  test "actor_name falls back to Sistema when there is no actor" do
    event = DeliveryEvent.new(action: "created", actor: nil)

    assert_equal "Sistema", event.actor_name
  end

  test "payload_data returns an empty hash for invalid JSON" do
    event = DeliveryEvent.new(action: "created", payload: "not json")

    assert_equal({}, event.payload_data)
  end

  test "recent orders by created_at desc" do
    older = DeliveryEvent.record(delivery: deliveries(:one), action: "created", payload: {})
    older.update_column(:created_at, 2.days.ago)
    newer = DeliveryEvent.record(delivery: deliveries(:one), action: "updated", payload: {})
    newer.update_column(:created_at, 1.day.ago)

    assert_equal [newer, older], DeliveryEvent.where(id: [older.id, newer.id]).recent.to_a
  end
end
```

- [ ] **Step 2: Correr el test para confirmar que pasa con el código actual (antes del refactor)**

Run: `bin/rails test test/models/delivery_event_test.rb`
Expected: 6 runs, 0 failures, 0 errors (el comportamiento ya existe; este test documenta el contrato antes de tocar nada).

- [ ] **Step 3: Crear el concern `EventLog`**

```ruby
# app/models/concerns/event_log.rb
module EventLog
  extend ActiveSupport::Concern

  included do
    validates :action, presence: true

    scope :recent, -> { order(created_at: :desc) }
    scope :for_action, ->(action) { where(action: action) }
    scope :by_actor, ->(user_id) { where(actor_id: user_id) }
  end

  def payload_data
    return {} if payload.blank?
    JSON.parse(payload)
  rescue JSON::ParserError => e
    Rails.logger.error("#{self.class}#payload_data error: #{e.message}")
    {}
  end

  def label
    self.class::ACTION_LABELS[action] || action.humanize
  end

  def color
    self.class::ACTION_COLORS[action] || "secondary"
  end

  def icon
    self.class::ACTION_ICONS[action] || "bi-circle"
  end

  def actor_name
    actor&.name || "Sistema"
  end

  class_methods do
    def record_event(attrs)
      create!(attrs.merge(created_at: Time.current))
    rescue => e
      Rails.logger.error("❌ #{name}.record falló [#{attrs[:action]}]: #{e.message}")
      nil
    end
  end
end
```

- [ ] **Step 4: Reemplazar `app/models/delivery_event.rb` para usar el concern (mismo comportamiento público)**

```ruby
# app/models/delivery_event.rb
class DeliveryEvent < ApplicationRecord
  include EventLog

  self.table_name = "delivery_events"

  # =========================================================================
  # Asociaciones
  # =========================================================================
  belongs_to :delivery
  belongs_to :actor, class_name: "User", optional: true

  # =========================================================================
  # Validaciones
  # =========================================================================
  validates :delivery_id, presence: true

  # =========================================================================
  # Constantes de acciones
  # =========================================================================
  ACTIONS = %w[
    rescheduled
    item_rescheduled
    items_bulk_confirmed
    sala_pickup_created
    service_case_created
    approved
    delivered
    warehousing_started
    warehousing_ended
    seller_reassigned
    created
    updated
    cancelled
    archived
    reopened
  ].freeze

  # =========================================================================
  # Factory method — punto único de creación
  # =========================================================================

  # Uso:
  #   DeliveryEvent.record(
  #     delivery: delivery,
  #     action: "rescheduled",
  #     actor: current_user,
  #     payload: { reason: "...", new_date: "..." }
  #   )
  def self.record(delivery:, action:, actor: nil, payload: {})
    record_event(
      delivery: delivery,
      action: action,
      actor: actor,
      payload: payload.to_json
    )
  end

  # =========================================================================
  # Presentación
  # =========================================================================

  ACTION_LABELS = {
    "rescheduled" => "Reagendada",
    "item_rescheduled" => "Ítem reagendado",
    "items_bulk_confirmed" => "Ítems confirmados",
    "sala_pickup_created" => "Retiro en Sala programado",
    "service_case_created" => "Caso de servicio creado",
    "approved" => "Aprobada",
    "delivered" => "Marcada como entregada",
    "warehousing_started" => "Bodegaje iniciado",
    "warehousing_ended" => "Bodegaje finalizado",
    "seller_reassigned" => "Vendedor reasignado",
    "created" => "Creada",
    "updated" => "Actualizada",
    "cancelled" => "Cancelada",
    "archived" => "Archivada",
    "reopened" => "Reabierta"
  }.freeze

  ACTION_COLORS = {
    "rescheduled" => "warning",
    "item_rescheduled" => "warning",
    "items_bulk_confirmed" => "success",
    "sala_pickup_created" => "info",
    "service_case_created" => "info",
    "approved" => "success",
    "delivered" => "success",
    "warehousing_started" => "secondary",
    "warehousing_ended" => "secondary",
    "seller_reassigned" => "primary",
    "created" => "success",
    "updated" => "primary",
    "cancelled" => "danger",
    "archived" => "dark",
    "reopened" => "warning"
  }.freeze

  ACTION_ICONS = {
    "rescheduled" => "bi-calendar-x",
    "item_rescheduled" => "bi-box-arrow-right",
    "items_bulk_confirmed" => "bi-check2-all",
    "sala_pickup_created" => "bi-shop",
    "service_case_created" => "bi-tools",
    "approved" => "bi-check-circle",
    "delivered" => "bi-truck",
    "warehousing_started" => "bi-box-seam",
    "warehousing_ended" => "bi-box-arrow-up",
    "seller_reassigned" => "bi-person-badge",
    "created" => "bi-plus-circle",
    "updated" => "bi-pencil",
    "cancelled" => "bi-x-circle",
    "archived" => "bi-archive",
    "reopened" => "bi-arrow-counterclockwise"
  }.freeze

  def actor_name
    actor&.name || "Sistema"
  end
end
```

- [ ] **Step 5: Correr el test de nuevo para confirmar que sigue pasando tras el refactor**

Run: `bin/rails test test/models/delivery_event_test.rb`
Expected: 6 runs, 0 failures, 0 errors — comportamiento idéntico, ahora respaldado por el concern.

- [ ] **Step 6: Commit**

```bash
git add app/models/concerns/event_log.rb app/models/delivery_event.rb test/models/delivery_event_test.rb
git commit -m "refactor: extraer concern EventLog desde DeliveryEvent"
```

---

### Task 3: Modelo `PlanEvent`

**Files:**
- Create: `app/models/plan_event.rb`
- Modify: `app/models/delivery_plan.rb:1-8` (agregar `has_many :plan_events, dependent: :destroy`)
- Test: `test/models/plan_event_test.rb`

**Interfaces:**
- Consumes: `EventLog` (Task 2), tabla `plan_events` (Task 1).
- Produces: `PlanEvent.record(delivery_plan:, action:, actor: nil, payload: {})` — usado por Tasks 6, 7, 8, 9, 10.
- Produces: `PlanEvent::ACTIONS` = `%w[created sent_to_logistics routes_created started finished aborted stop_added stop_removed]`.

- [ ] **Step 1: Escribir el test (falla porque `PlanEvent` no existe todavía)**

```ruby
# test/models/plan_event_test.rb
require "test_helper"

class PlanEventTest < ActiveSupport::TestCase
  test "record creates an event with the given action, actor and payload" do
    event = PlanEvent.record(
      delivery_plan: delivery_plans(:one),
      action: "started",
      actor: users(:one),
      payload: {note: "ok"}
    )

    assert event.persisted?
    assert_equal "started", event.action
    assert_equal users(:one).id, event.actor_id
    assert_equal({"note" => "ok"}, event.payload_data)
  end

  test "record returns nil and does not raise when creation fails" do
    result = PlanEvent.record(delivery_plan: nil, action: "started")

    assert_nil result
  end

  test "label color and icon are looked up from the action dictionaries" do
    event = PlanEvent.new(action: "aborted")

    assert_equal "Abortado", event.label
    assert_equal "danger", event.color
    assert_equal "bi-x-circle", event.icon
  end

  test "destroying the delivery_plan destroys its plan_events" do
    plan = DeliveryPlan.create!(week: "12", year: 2026, status: :draft)
    PlanEvent.record(delivery_plan: plan, action: "created")

    assert_difference -> { PlanEvent.count }, -(plan.plan_events.count) do
      plan.destroy!
    end
  end
end
```

- [ ] **Step 2: Correr el test para confirmar que falla**

Run: `bin/rails test test/models/plan_event_test.rb`
Expected: FAIL con `NameError: uninitialized constant PlanEvent`.

- [ ] **Step 3: Crear el modelo**

```ruby
# app/models/plan_event.rb
class PlanEvent < ApplicationRecord
  include EventLog

  belongs_to :delivery_plan
  belongs_to :actor, class_name: "User", optional: true

  validates :delivery_plan_id, presence: true

  ACTIONS = %w[
    created
    sent_to_logistics
    routes_created
    started
    finished
    aborted
    stop_added
    stop_removed
  ].freeze

  ACTION_LABELS = {
    "created" => "Plan creado",
    "sent_to_logistics" => "Enviado a logística",
    "routes_created" => "Ruta creada",
    "started" => "Iniciado",
    "finished" => "Finalizado",
    "aborted" => "Abortado",
    "stop_added" => "Parada agregada",
    "stop_removed" => "Parada quitada"
  }.freeze

  ACTION_COLORS = {
    "created" => "success",
    "sent_to_logistics" => "primary",
    "routes_created" => "primary",
    "started" => "info",
    "finished" => "success",
    "aborted" => "danger",
    "stop_added" => "secondary",
    "stop_removed" => "warning"
  }.freeze

  ACTION_ICONS = {
    "created" => "bi-plus-circle",
    "sent_to_logistics" => "bi-send",
    "routes_created" => "bi-signpost-2",
    "started" => "bi-play-circle",
    "finished" => "bi-check-circle",
    "aborted" => "bi-x-circle",
    "stop_added" => "bi-pin-map",
    "stop_removed" => "bi-pin-map-fill"
  }.freeze

  def self.record(delivery_plan:, action:, actor: nil, payload: {})
    record_event(
      delivery_plan: delivery_plan,
      action: action,
      actor: actor,
      payload: payload.to_json
    )
  end
end
```

- [ ] **Step 4: Agregar la asociación en `DeliveryPlan`**

En `app/models/delivery_plan.rb`, reemplazar:

```ruby
class DeliveryPlan < ApplicationRecord
  has_paper_trail
  has_many :delivery_plan_assignments, -> { order(:stop_order) }, dependent: :destroy
  has_many :deliveries, through: :delivery_plan_assignments
  has_many :delivery_plan_locations, dependent: :destroy
  belongs_to :driver, class_name: "User", optional: true
```

por:

```ruby
class DeliveryPlan < ApplicationRecord
  has_paper_trail
  has_many :delivery_plan_assignments, -> { order(:stop_order) }, dependent: :destroy
  has_many :deliveries, through: :delivery_plan_assignments
  has_many :delivery_plan_locations, dependent: :destroy
  has_many :plan_events, dependent: :destroy
  belongs_to :driver, class_name: "User", optional: true
```

- [ ] **Step 5: Correr el test para confirmar que pasa**

Run: `bin/rails test test/models/plan_event_test.rb`
Expected: 4 runs, 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/models/plan_event.rb app/models/delivery_plan.rb test/models/plan_event_test.rb
git commit -m "feat: agregar modelo PlanEvent para narrativa de negocio de delivery_plans"
```

---

### Task 4: Módulo `AuditActor`

**Files:**
- Create: `app/models/audit_actor.rb`
- Test: `test/models/audit_actor_test.rb`

**Interfaces:**
- Produces: `AuditActor.current` → `User` o `nil`, leyendo `PaperTrail.request.whodunnit`. Usado por Tasks 6, 7, 8, 9, 10, 14.

- [ ] **Step 1: Escribir el test**

```ruby
# test/models/audit_actor_test.rb
require "test_helper"

class AuditActorTest < ActiveSupport::TestCase
  test "current resolves the user from PaperTrail's whodunnit" do
    PaperTrail.request(whodunnit: users(:one).id.to_s) do
      assert_equal users(:one), AuditActor.current
    end
  end

  test "current returns nil when there is no whodunnit set" do
    PaperTrail.request(whodunnit: nil) do
      assert_nil AuditActor.current
    end
  end

  test "current returns nil when whodunnit points to a non-existent user" do
    PaperTrail.request(whodunnit: "999999") do
      assert_nil AuditActor.current
    end
  end
end
```

- [ ] **Step 2: Correr el test para confirmar que falla**

Run: `bin/rails test test/models/audit_actor_test.rb`
Expected: FAIL con `NameError: uninitialized constant AuditActor`.

- [ ] **Step 3: Crear el módulo**

```ruby
# app/models/audit_actor.rb
module AuditActor
  def self.current
    User.find_by(id: PaperTrail.request.whodunnit)
  end
end
```

- [ ] **Step 4: Correr el test para confirmar que pasa**

Run: `bin/rails test test/models/audit_actor_test.rb`
Expected: 3 runs, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add app/models/audit_actor.rb test/models/audit_actor_test.rb
git commit -m "feat: agregar AuditActor para resolver el actor fuera del controlador"
```

---

### Task 5: Nuevas acciones de `DeliveryEvent` (`route_started`, `failed`) + descripciones

**Files:**
- Modify: `app/models/delivery_event.rb` (constantes `ACTIONS`/`ACTION_LABELS`/`ACTION_COLORS`/`ACTION_ICONS`)
- Modify: `app/helpers/delivery_events_helper.rb` (`delivery_event_description`)
- Test: `test/helpers/delivery_events_helper_test.rb` (nuevo)

**Interfaces:**
- Produces: acciones `"route_started"` y `"failed"` disponibles en `DeliveryEvent`. Usadas por Tasks 8 y 10.

- [ ] **Step 1: Escribir el test de las descripciones nuevas (falla porque las acciones no existen)**

```ruby
# test/helpers/delivery_events_helper_test.rb
require "test_helper"

class DeliveryEventsHelperTest < ActionView::TestCase
  include DeliveryEventsHelper

  test "describes a route_started event" do
    event = DeliveryEvent.new(action: "route_started", payload: {delivery_plan_id: 5, stop_order: 2}.to_json)

    assert_equal "Entrega en ruta (parada del plan iniciada)", delivery_event_description(event)
  end

  test "describes a failed event with reason and new delivery id" do
    event = DeliveryEvent.new(
      action: "failed",
      payload: {reason: "Cliente no se encontraba", new_delivery_id: 99}.to_json
    )

    assert_equal "Entrega fracasada — Cliente no se encontraba (Reagendada: Entrega #99)", delivery_event_description(event)
  end

  test "describes a failed event without a reason" do
    event = DeliveryEvent.new(action: "failed", payload: {}.to_json)

    assert_equal "Entrega fracasada", delivery_event_description(event)
  end
end
```

- [ ] **Step 2: Correr el test para confirmar que falla**

Run: `bin/rails test test/helpers/delivery_events_helper_test.rb`
Expected: FAIL — `delivery_event_description` cae al `else` (`event.label`) porque `"route_started"`/`"failed"` no están en `ACTION_LABELS` todavía, así que no coincide con el texto esperado.

- [ ] **Step 3: Agregar las acciones nuevas a `app/models/delivery_event.rb`**

En el array `ACTIONS`, agregar `route_started` y `failed`:

```ruby
  ACTIONS = %w[
    rescheduled
    item_rescheduled
    items_bulk_confirmed
    sala_pickup_created
    service_case_created
    approved
    delivered
    warehousing_started
    warehousing_ended
    seller_reassigned
    route_started
    failed
    created
    updated
    cancelled
    archived
    reopened
  ].freeze
```

En `ACTION_LABELS`, agregar:

```ruby
    "route_started" => "En ruta (parada de plan iniciada)",
    "failed" => "Entrega fracasada",
```

En `ACTION_COLORS`, agregar:

```ruby
    "route_started" => "info",
    "failed" => "danger",
```

En `ACTION_ICONS`, agregar:

```ruby
    "route_started" => "bi-truck",
    "failed" => "bi-exclamation-triangle",
```

- [ ] **Step 4: Agregar los casos en `app/helpers/delivery_events_helper.rb`**

Dentro del `case event.action`, antes de `when "created"`, agregar:

```ruby
    when "route_started"
      "Entrega en ruta (parada del plan iniciada)"

    when "failed"
      reason = data["reason"].presence
      new_id = data["new_delivery_id"]
      parts = ["Entrega fracasada"]
      parts << "— #{reason}" if reason
      parts << "(Reagendada: Entrega ##{new_id})" if new_id
      parts.join(" ")
```

- [ ] **Step 5: Correr el test para confirmar que pasa**

Run: `bin/rails test test/helpers/delivery_events_helper_test.rb`
Expected: 3 runs, 0 failures, 0 errors.

- [ ] **Step 6: Correr la suite completa de `delivery_event` para confirmar que no rompimos nada**

Run: `bin/rails test test/models/delivery_event_test.rb test/helpers/delivery_events_helper_test.rb`
Expected: 9 runs, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add app/models/delivery_event.rb app/helpers/delivery_events_helper.rb test/helpers/delivery_events_helper_test.rb
git commit -m "feat: agregar acciones route_started y failed a DeliveryEvent"
```

---

### Task 6: Ciclo de vida de `DeliveryPlan` → `PlanEvent` (creación + cambios de status)

**Files:**
- Modify: `app/models/delivery_plan.rb` (callbacks + métodos privados)
- Test: `test/models/delivery_plan_test.rb` (reemplazo del stub vacío)

**Interfaces:**
- Consumes: `PlanEvent.record` (Task 3), `AuditActor.current` (Task 4).
- Produces: cada transición de `status` deja un `PlanEvent`. Las tareas siguientes no dependen de signatures nuevas aquí (son callbacks internos).

- [ ] **Step 1: Escribir los tests (fallan porque los callbacks no existen)**

```ruby
# test/models/delivery_plan_test.rb
require "test_helper"

class DeliveryPlanTest < ActiveSupport::TestCase
  test "creating a plan records a created PlanEvent" do
    plan = DeliveryPlan.create!(week: "25", year: 2026, status: :draft)

    assert_equal "created", plan.plan_events.last.action
  end

  test "start! records a started PlanEvent" do
    plan = delivery_plans(:one)
    plan.update!(status: :routes_created)

    assert_difference -> { plan.plan_events.count }, 1 do
      plan.start!
    end

    assert_equal "started", plan.plan_events.last.action
  end

  test "finish! records a finished PlanEvent" do
    plan = delivery_plans(:one)
    plan.update!(status: :in_progress)
    plan.delivery_plan_assignments.destroy_all

    assert_difference -> { plan.plan_events.count }, 1 do
      plan.finish!
    end

    assert_equal "finished", plan.plan_events.last.action
  end

  test "abort! records an aborted PlanEvent" do
    plan = delivery_plans(:one)
    plan.update!(status: :routes_created)

    assert_difference -> { plan.plan_events.count }, 1 do
      plan.abort!
    end

    assert_equal "aborted", plan.plan_events.last.action
  end

  test "moving back to draft does not record a PlanEvent (no acción mapeada)" do
    plan = delivery_plans(:one)
    plan.update!(status: :sent_to_logistics)

    assert_no_difference -> { plan.plan_events.count } do
      plan.update!(status: :draft)
    end
  end

  test "PlanEvent actor is resolved via AuditActor when no current_user is in scope" do
    PaperTrail.request(whodunnit: users(:one).id.to_s) do
      plan = DeliveryPlan.create!(week: "40", year: 2026, status: :draft)

      assert_equal users(:one), plan.plan_events.last.actor
    end
  end

  test "assigning a driver to a confirmed draft plan records routes_created exactly once (nested-save de-dup guard)" do
    plan = delivery_plans(:one)
    plan.update!(status: :draft)
    plan.deliveries.each { |d| d.update_columns(status: Delivery.statuses[:in_plan]) }

    assert_difference -> { plan.plan_events.where(action: "routes_created").count }, 1 do
      plan.update!(driver: users(:one))
    end
  end

  test "removing a driver from a sent_to_logistics plan does not record a PlanEvent (draft is unmapped, and the nested-save guard would also prevent a double record if it were mapped)" do
    plan = delivery_plans(:one)
    plan.update_columns(status: DeliveryPlan.statuses[:sent_to_logistics], driver_id: users(:one).id)

    assert_no_difference -> { plan.plan_events.count } do
      plan.update!(driver_id: nil)
    end
  end
end
```

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/models/delivery_plan_test.rb`
Expected: FAIL — `plan.plan_events` está vacío en todos los casos (los callbacks no existen aún).

- [ ] **Step 3: Agregar los callbacks en `app/models/delivery_plan.rb`**

Reemplazar el bloque de callbacks (líneas 9-12 originales):

```ruby
  before_destroy :ensure_deletable

  after_update :notify_driver_assignment, if: :saved_change_to_driver_id?
  after_update :update_status_on_driver_change, if: :saved_change_to_driver_id?
  before_destroy :flush_assignments
```

por:

```ruby
  before_destroy :ensure_deletable

  after_create :record_created_event
  after_update :notify_driver_assignment, if: :saved_change_to_driver_id?
  after_update :update_status_on_driver_change, if: :saved_change_to_driver_id?
  after_update :record_status_change_event, if: :saved_change_to_status?
  before_destroy :flush_assignments
```

- [ ] **Step 4: Agregar los métodos privados al final del archivo**

Reemplazar el bloque `private` final (las últimas líneas del archivo):

```ruby
  private

  def notify_driver_assignment
    NotificationService.notify_route_assigned(self) if driver_id.present?
  end

  def update_status_on_driver_change
    if driver_id.present?
      if all_deliveries_confirmed?
        update_column(:status, DeliveryPlan.statuses[:routes_created]) if status_draft?
      else
        errors.add(:base, "No puedes asignar a logística mientras existan entregas sin confirmar")
      end

      self.status = :draft unless all_deliveries_confirmed?
    elsif status_sent_to_logistics?
      update_column(:status, DeliveryPlan.statuses[:draft])
    end
  end

  def flush_assignments
    delivery_plan_assignments.destroy_all
  end
end
```

por:

```ruby
  private

  STATUS_TO_PLAN_EVENT_ACTION = {
    "sent_to_logistics" => "sent_to_logistics",
    "routes_created" => "routes_created",
    "in_progress" => "started",
    "completed" => "finished",
    "aborted" => "aborted"
  }.freeze

  def record_created_event
    PlanEvent.record(delivery_plan: self, action: "created", actor: AuditActor.current)
  end

  def record_status_change_event
    action = STATUS_TO_PLAN_EVENT_ACTION[status]
    return unless action
    return if action == @recorded_plan_event_action

    @recorded_plan_event_action = action
    PlanEvent.record(delivery_plan: self, action: action, actor: AuditActor.current)
  end

  def notify_driver_assignment
    NotificationService.notify_route_assigned(self) if driver_id.present?
  end

  def update_status_on_driver_change
    if driver_id.present?
      if all_deliveries_confirmed?
        update!(status: :routes_created) if status_draft?
      else
        errors.add(:base, "No puedes asignar a logística mientras existan entregas sin confirmar")
      end

      self.status = :draft unless all_deliveries_confirmed?
    elsif status_sent_to_logistics?
      update!(status: :draft)
    end
  end

  def flush_assignments
    delivery_plan_assignments.destroy_all
  end
end
```

**Nota de seguridad sobre recursión (corregida durante implementación — ver Task 6 en el ledger):** `update_status_on_driver_change` corre dentro de un `after_update` (`if: :saved_change_to_driver_id?`). Al cambiar de `update_column` a `update!`, ese método dispara un *nuevo* ciclo de guardado anidado. Ese guardado anidado no cambia `driver_id`, así que `saved_change_to_driver_id?` es `false` en él y `update_status_on_driver_change` no se vuelve a disparar — no hay recursión infinita.

Sin embargo, **el guardado anidado SÍ contamina el chequeo `saved_change_to_status?` de la cadena `after_update` externa**: Rails rastrea `saved_changes`/`mutations_before_last_save` en el mismo objeto en memoria, así que cuando la cadena externa llega a evaluar su propio callback `record_status_change_event, if: :saved_change_to_status?` (registrado después de `update_status_on_driver_change` en la lista), ese chequeo ya refleja los cambios del guardado anidado, no los del guardado externo — y el callback externo se dispara una segunda vez para el mismo cambio de status, duplicando el `PlanEvent`. Por eso `record_status_change_event` lleva un guard de idempotencia (`@recorded_plan_event_action`): es una variable de instancia que persiste durante la vida del objeto Ruby en memoria (sobrevive al guardado anidado, ya que es el mismo objeto), así que la segunda invocación para la misma acción se descarta. Si el objeto se recarga de la base de datos (`reload`/`find` nuevamente) y la misma transición vuelve a ocurrir legítimamente más tarde, el guard se reinicia solo porque es un objeto Ruby nuevo — no hay riesgo de bloquear eventos legítimos futuros.

- [ ] **Step 5: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/models/delivery_plan_test.rb`
Expected: 8 runs, 0 failures, 0 errors.

**Nota sobre fixtures:** si `test/fixtures/delivery_plans.yml` todavía tiene los valores placeholder del scaffold (`week: MyString`, `year: 1`), estos tests van a fallar por validaciones (`year`/`week` numericality) antes de llegar a probar nada de `PlanEvent` — ningún test anterior en la suite había hecho `.update!`/`.save!` directo sobre ese fixture. Corregir el fixture a valores válidos (ej. `week: "1"`, `year: 2026` para `one` y `two`) es necesario y está dentro del alcance de este task.

- [ ] **Step 6: Commit**

```bash
git add app/models/delivery_plan.rb test/models/delivery_plan_test.rb test/fixtures/delivery_plans.yml
git commit -m "feat: registrar PlanEvent en creación y cambios de status de DeliveryPlan"
```

---

### Task 7: Paradas agregadas/quitadas → `PlanEvent` (`DeliveryPlanAssignment` create/destroy)

**Files:**
- Modify: `app/models/delivery_plan_assignment.rb` (callbacks + métodos privados)
- Test: `test/models/delivery_plan_assignment_test.rb` (reemplazo del stub vacío)

**Interfaces:**
- Consumes: `PlanEvent.record` (Task 3), `AuditActor.current` (Task 4).
- Produces: `stop_added`/`stop_removed` con payload `{"delivery_id" => Integer, "delivery_label" => String}`. Usado por la descripción de Task 18 (`plan_event_description`).

- [ ] **Step 1: Escribir los tests (fallan porque los callbacks no existen)**

```ruby
# test/models/delivery_plan_assignment_test.rb
require "test_helper"

class DeliveryPlanAssignmentTest < ActiveSupport::TestCase
  test "creating an assignment records a stop_added PlanEvent on its plan" do
    plan = DeliveryPlan.create!(week: "30", year: 2026, status: :draft)
    delivery = deliveries(:one)
    delivery.update!(status: :scheduled)

    assert_difference -> { plan.plan_events.where(action: "stop_added").count }, 1 do
      plan.delivery_plan_assignments.create!(delivery: delivery)
    end

    event = plan.plan_events.where(action: "stop_added").last
    assert_equal delivery.id, event.payload_data["delivery_id"]
  end

  test "destroying an assignment records a stop_removed PlanEvent on its plan" do
    assignment = delivery_plan_assignments(:one)
    plan = assignment.delivery_plan

    assert_difference -> { plan.plan_events.where(action: "stop_removed").count }, 1 do
      assignment.destroy!
    end
  end
end
```

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: FAIL — `plan.plan_events.where(action: "stop_added"/"stop_removed")` está vacío.

- [ ] **Step 3: Agregar los callbacks**

Reemplazar:

```ruby
  # Callbacks
  after_create :change_deliveries_statuses
  after_destroy :revert_statuses
```

por:

```ruby
  # Callbacks
  after_create :change_deliveries_statuses
  after_create :record_stop_added
  after_destroy :revert_statuses
  after_destroy :record_stop_removed
```

- [ ] **Step 4: Agregar los métodos privados**

Al final de la sección `MÉTODOS PRIVADOS` (después de `revert_statuses`, antes del `end` final de la clase), agregar:

```ruby
  def record_stop_added
    PlanEvent.record(
      delivery_plan: delivery_plan,
      action: "stop_added",
      actor: AuditActor.current,
      payload: {delivery_id: delivery_id, delivery_label: delivery_label_for_event}
    )
  end

  def record_stop_removed
    PlanEvent.record(
      delivery_plan: delivery_plan,
      action: "stop_removed",
      actor: AuditActor.current,
      payload: {delivery_id: delivery_id, delivery_label: delivery_label_for_event}
    )
  end

  def delivery_label_for_event
    "Pedido #{delivery.order_number} — #{delivery.delivery_address&.address}"
  rescue StandardError
    "Entrega ##{delivery_id}"
  end
```

- [ ] **Step 5: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/models/delivery_plan_assignment.rb test/models/delivery_plan_assignment_test.rb
git commit -m "feat: registrar PlanEvent al agregar/quitar paradas de un plan"
```

---

### Task 8: Instrumentar `DeliveryPlanAssignment#start!`

**Files:**
- Modify: `app/models/delivery_plan_assignment.rb` (método `start!`)
- Test: `test/models/delivery_plan_assignment_test.rb` (agregar tests)

**Interfaces:**
- Consumes: `DeliveryEvent.record` (existente), acción `"route_started"` (Task 5), `AuditActor.current` (Task 4).
- Produces: cada llamada a `start!` deja una versión PaperTrail por cada `DeliveryItem` tocado (antes invisible) y un `DeliveryEvent` `"route_started"`.

- [ ] **Step 1: Escribir los tests (fallan con el código actual)**

```ruby
  test "start! moves the delivery to in_route via update! (PaperTrail visible) and records a route_started DeliveryEvent" do
    assignment = delivery_plan_assignments(:one)
    assignment.delivery.update!(status: :ready_to_deliver)
    assignment.delivery.delivery_items.each { |i| i.update!(status: :in_plan) }
    versions_before = PaperTrail::Version.where(item_type: "Delivery", item_id: assignment.delivery.id).count

    assert_difference -> { DeliveryEvent.where(action: "route_started").count }, 1 do
      assignment.start!
    end

    assert_equal "in_route", assignment.delivery.reload.status
    assert_operator PaperTrail::Version.where(item_type: "Delivery", item_id: assignment.delivery.id).count, :>, versions_before
  end

  test "start! leaves a PaperTrail version on each item moved from in_plan to in_route" do
    assignment = delivery_plan_assignments(:one)
    assignment.delivery.update!(status: :in_plan)
    item = assignment.delivery.delivery_items.first
    item.update!(status: :in_plan)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      assignment.start!
    end

    assert_equal "in_route", item.reload.status
  end
```

(agregar estos dos tests dentro de la clase `DeliveryPlanAssignmentTest` creada en Task 7)

**Nota sobre la precondición de items:** el primer test debe poner los items en `:in_plan` antes de llamar a `start!`. Si los items quedan en su estado de fixture original (`confirmed`), el `find_each` de `start!` no los toca (busca `status: in_plan`), y `delivery.update_status_based_on_items` —que se llama al final de `start!`— recalcula el status de la entrega a partir de sus items y lo regresa a `in_plan` en vez de dejarlo en `in_route`, haciendo fallar la aserción final. Por eso ambos tests fuerzan `:in_plan` en los items antes de invocar `start!`.

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: FAIL — `DeliveryEvent.where(action: "route_started")` vacío, y `delivery.update_column`/items `update_all` no generan versiones PaperTrail.

- [ ] **Step 3: Reemplazar el método `start!`**

```ruby
  def start!
    return true if in_route? || completed?

    transaction do
      update!(status: :in_route, started_at: Time.current)

      if delivery.in_plan? || delivery.ready_to_deliver?
        delivery.update!(status: :in_route)
      end

      delivery.delivery_items.where(status: DeliveryItem.statuses[:in_plan]).find_each do |item|
        item.update!(status: :in_route)
      end

      delivery.update_status_based_on_items

      DeliveryEvent.record(
        delivery: delivery,
        action: "route_started",
        actor: AuditActor.current,
        payload: {delivery_plan_id: delivery_plan_id, stop_order: stop_order}
      )
    end

    true
  end
```

- [ ] **Step 4: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: 4 runs, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add app/models/delivery_plan_assignment.rb test/models/delivery_plan_assignment_test.rb
git commit -m "feat: instrumentar DeliveryPlanAssignment#start! (PaperTrail visible + DeliveryEvent route_started)"
```

---

### Task 9: Instrumentar `DeliveryPlanAssignment#complete!`

**Files:**
- Modify: `app/models/delivery_plan_assignment.rb` (método `complete!`)
- Test: `test/models/delivery_plan_assignment_test.rb` (agregar test)

**Interfaces:**
- Consumes: `DeliveryEvent.record` (existente, acción `"delivered"` ya existía), `AuditActor.current` (Task 4).

- [ ] **Step 1: Escribir el test**

```ruby
  test "complete! marks the delivery as delivered and records a delivered DeliveryEvent" do
    assignment = delivery_plan_assignments(:one)

    assert_difference -> { DeliveryEvent.where(action: "delivered", delivery_id: assignment.delivery_id).count }, 1 do
      assignment.complete!
    end

    assert_equal "completed", assignment.reload.status
    event = DeliveryEvent.where(action: "delivered", delivery_id: assignment.delivery_id).last
    assert_equal "plan_assignment", event.payload_data["via"]
  end
```

- [ ] **Step 2: Correr el test para confirmar que falla**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: FAIL — no se registra ningún `DeliveryEvent` desde `complete!`.

- [ ] **Step 3: Reemplazar el método `complete!`**

```ruby
  def complete!
    return true if completed?

    transaction do
      delivery.mark_as_delivered!
      update!(status: :completed, completed_at: Time.current)

      DeliveryEvent.record(
        delivery: delivery,
        action: "delivered",
        actor: AuditActor.current,
        payload: {via: "plan_assignment"}
      )
    end

    true
  end
```

- [ ] **Step 4: Correr el test para confirmar que pasa**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: 5 runs, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add app/models/delivery_plan_assignment.rb test/models/delivery_plan_assignment_test.rb
git commit -m "feat: registrar DeliveryEvent delivered desde DeliveryPlanAssignment#complete!"
```

---

### Task 10: Instrumentar `mark_as_failed!` / `DeliveryFailureService`

**Files:**
- Modify: `app/services/delivery_failure_service.rb`
- Modify: `app/models/delivery_plan_assignment.rb:75` (pasar `failed_by` al servicio)
- Test: `test/services/delivery_failure_service_test.rb` (nuevo)

**Interfaces:**
- Consumes: `DeliveryEvent.record` (existente, acción `"failed"` de Task 5), `AuditActor.current` (Task 4).
- Produces: `DeliveryFailureService.new(delivery, reason: nil, reschedule_days: 7, failed_by: nil)` — nuevo kwarg opcional, no rompe el único call site existente.

- [ ] **Step 1: Escribir el test (falla con el código actual)**

```ruby
# test/services/delivery_failure_service_test.rb
require "test_helper"

class DeliveryFailureServiceTest < ActiveSupport::TestCase
  test "marks the delivery failed, clones it, and records a failed DeliveryEvent with the new delivery id" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(status: :confirmed)

    new_delivery = nil
    assert_difference -> { DeliveryEvent.where(action: "failed").count }, 1 do
      new_delivery = DeliveryFailureService.new(
        delivery, reason: "Cliente no se encontraba", failed_by: users(:one)
      ).call
    end

    event = DeliveryEvent.where(action: "failed").last
    assert_equal delivery.id, event.delivery_id
    assert_equal new_delivery.id, event.payload_data["new_delivery_id"]
    assert_equal users(:one).id, event.actor_id
  end

  test "item status changes during failure are visible in PaperTrail" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(status: :confirmed)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      DeliveryFailureService.new(delivery, reason: "test").call
    end
  end
end
```

- [ ] **Step 2: Correr el test para confirmar que falla**

Run: `bin/rails test test/services/delivery_failure_service_test.rb`
Expected: FAIL — `ArgumentError: unknown keyword: :failed_by` y no hay ningún `DeliveryEvent` con acción `"failed"`.

- [ ] **Step 3: Reemplazar `app/services/delivery_failure_service.rb`**

```ruby
class DeliveryFailureService
  def initialize(delivery, reason: nil, reschedule_days: 7, failed_by: nil)
    @delivery = delivery
    @reason = reason || "Entrega fracasada - reagendada automáticamente"
    @reschedule_days = reschedule_days
    @failed_by = failed_by
  end

  def call
    ActiveRecord::Base.transaction do
      # 1. Marcar la entrega original como fracasada
      mark_as_failed!

      # 2. Clonar la entrega para una semana después
      new_delivery = clone_delivery!

      # 3. Registrar el evento de negocio con el id de la nueva entrega
      record_failure_event(new_delivery)

      # 4. Notificar a los involucrados
      notify_failure(new_delivery)

      new_delivery
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Error al procesar entrega fracasada: #{e.message}")
    raise
  end

  private

  def mark_as_failed!
    @delivery.update!(
      status: :failed,
      reschedule_reason: @reason
    )

    # Marcar todos los delivery_items como failed
    @delivery.delivery_items.where.not(status: [:delivered, :cancelled]).find_each do |item|
      item.update!(status: :failed)
    end
  end

  def record_failure_event(new_delivery)
    DeliveryEvent.record(
      delivery: @delivery,
      action: "failed",
      actor: @failed_by || AuditActor.current,
      payload: {reason: @reason, new_delivery_id: new_delivery.id}
    )
  end

  def clone_delivery!
    new_date = @delivery.delivery_date + @reschedule_days.days

    # Crear nueva entrega
    new_delivery = Delivery.create!(
      order: @delivery.order,
      delivery_address: @delivery.delivery_address,
      delivery_date: new_date,
      contact_name: @delivery.contact_name,
      contact_phone: @delivery.contact_phone,
      contact_id: @delivery.contact_id,
      delivery_time_preference: @delivery.delivery_time_preference,
      delivery_notes: "Reagendada por entrega fracasada del #{@delivery.delivery_date.strftime("%d/%m/%Y")}. Motivo: #{@reason}",
      delivery_type: @delivery.delivery_type,
      status: :scheduled,
      approved: true
    )

    # Clonar delivery_items que no fueron entregados
    @delivery.delivery_items.where.not(status: [:delivered, :cancelled]).each do |item|
      DeliveryItem.create!(
        delivery: new_delivery,
        order_item: item.order_item,
        quantity_delivered: item.quantity_delivered,
        status: :pending,
        service_case: item.service_case,
        notes: item.notes
      )
    end

    new_delivery
  end

  def notify_failure(new_delivery)
    users = []
    # Logística y producción
    users += User.where(role: [:logistics, :production_manager])
    # Vendedor del pedido
    users << @delivery.order.seller.user if @delivery.order.seller&.user.present?

    message = <<~MSG.strip
      La entrega del pedido #{@delivery.order.number} programada para #{I18n.l(@delivery.delivery_date, format: :long)} fracasó.
      Se creó una nueva entrega para #{I18n.l(new_delivery.delivery_date, format: :long)}.
    MSG

    NotificationService.create_for_users(users.compact.uniq, new_delivery, message, type: "delivery_failed")
  end
end
```

- [ ] **Step 4: Pasar `failed_by` desde `DeliveryPlanAssignment#mark_as_failed!`**

En `app/models/delivery_plan_assignment.rb`, reemplazar:

```ruby
      DeliveryFailureService.new(delivery, reason: reason).call
```

por:

```ruby
      DeliveryFailureService.new(delivery, reason: reason, failed_by: failed_by).call
```

- [ ] **Step 5: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/services/delivery_failure_service_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [ ] **Step 6: Correr la suite de `delivery_plan_assignment` para confirmar que no se rompió nada**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: 5 runs, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add app/services/delivery_failure_service.rb app/models/delivery_plan_assignment.rb test/services/delivery_failure_service_test.rb
git commit -m "feat: registrar DeliveryEvent failed y exponer items afectados en PaperTrail"
```

---

### Task 11: `change_deliveries_statuses`/`revert_statuses` → PaperTrail visible

**Files:**
- Modify: `app/models/delivery_plan_assignment.rb` (métodos `change_deliveries_statuses`/`revert_statuses`)
- Test: `test/models/delivery_plan_assignment_test.rb` (agregar tests)

**Interfaces:**
- No expone nada nuevo a otras tareas; es una corrección interna de visibilidad PaperTrail.

- [ ] **Step 1: Escribir los tests**

```ruby
  test "change_deliveries_statuses leaves a PaperTrail version on each confirmed item it moves to in_plan" do
    plan = DeliveryPlan.create!(week: "31", year: 2026, status: :sent_to_logistics)
    delivery = deliveries(:one)
    delivery.update!(status: :ready_to_deliver)
    item = delivery_items(:one)
    item.update!(status: :confirmed)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      plan.delivery_plan_assignments.create!(delivery: delivery)
    end

    assert_equal "in_plan", item.reload.status
  end

  test "revert_statuses leaves a PaperTrail version on each item it moves back to confirmed" do
    assignment = delivery_plan_assignments(:one)
    item = assignment.delivery.delivery_items.first
    item.update!(status: :in_plan)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      assignment.destroy!
    end

    assert_equal "confirmed", item.reload.status
  end
```

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: FAIL — `update_all` no genera versiones PaperTrail para el item.

- [ ] **Step 3: Reemplazar los dos métodos**

```ruby
  def change_deliveries_statuses
    return if delivery_plan.draft? && delivery.scheduled?

    transaction do
      delivery.delivery_items.where(status: DeliveryItem.statuses[:confirmed]).find_each do |item|
        item.update!(status: :in_plan)
      end

      delivery.update!(status: :in_plan)

      delivery.update_status_based_on_items
    end
  end

  def revert_statuses
    transaction do
      delivery.delivery_items.where(status: DeliveryItem.statuses[:in_plan]).find_each do |item|
        item.update!(status: :confirmed)
      end

      delivery.update_status_based_on_items
    end
  end
```

- [ ] **Step 4: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/models/delivery_plan_assignment_test.rb`
Expected: 7 runs, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add app/models/delivery_plan_assignment.rb test/models/delivery_plan_assignment_test.rb
git commit -m "fix: hacer visibles en PaperTrail las cascadas de change_deliveries_statuses/revert_statuses"
```

---

### Task 12: `DeliveryPlan#recalculate_load_status!`/`#mark_all_loaded!` → PaperTrail visible

**Files:**
- Modify: `app/models/delivery_plan.rb` (métodos `recalculate_load_status!`, `mark_all_loaded!`)
- Test: `test/models/delivery_plan_test.rb` (agregar tests)

**Interfaces:** ninguna nueva — corrección interna de visibilidad PaperTrail.

- [ ] **Step 1: Escribir los tests**

```ruby
  test "recalculate_load_status! leaves a PaperTrail version on the plan" do
    plan = delivery_plans(:one)
    item = delivery_items(:one)
    item.update!(load_status: :loaded)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryPlan", item_id: plan.id).count }, 1 do
      plan.recalculate_load_status!
    end
  end

  test "mark_all_loaded! leaves a PaperTrail version on each affected item" do
    plan = delivery_plans(:one)
    item = delivery_items(:one)
    item.update!(load_status: :unloaded)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      plan.mark_all_loaded!
    end

    assert_equal "loaded", item.reload.load_status
  end
```

(agregar dentro de `DeliveryPlanTest`, creada en Task 6)

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/models/delivery_plan_test.rb`
Expected: FAIL — `update_column`/`update_all` no generan versiones PaperTrail.

- [ ] **Step 3: Reemplazar `recalculate_load_status!`**

```ruby
  def recalculate_load_status!
    all_items = DeliveryItem.joins(:delivery)
      .where(deliveries: {id: delivery_ids})

    return if all_items.empty?

    loaded_count = all_items.where(load_status: DeliveryItem.load_statuses[:loaded]).count
    missing_count = all_items.where(load_status: DeliveryItem.load_statuses[:missing]).count
    total_count = all_items.count

    new_status = if missing_count > 0
      :some_missing
    elsif loaded_count == total_count
      :all_loaded
    elsif loaded_count > 0
      :partial
    else
      :empty
    end

    update!(load_status: new_status)

    if new_status == :all_loaded && !status_completed?
      status_completed!
    end
  end
```

- [ ] **Step 4: Reemplazar `mark_all_loaded!`**

```ruby
  def mark_all_loaded!
    transaction do
      DeliveryItem
        .joins(:delivery)
        .where(deliveries: {id: delivery_ids})
        .where.not(load_status: DeliveryItem.load_statuses[:missing])
        .find_each do |item|
          item.update!(load_status: :loaded, status: :loaded_on_truck)
        end

      deliveries.each do |delivery|
        delivery.recalculate_load_status!
        delivery.update_status_based_on_items
      end

      recalculate_load_status!
    end
  end
```

**Nota:** `Delivery#recalculate_load_status!` (distinto del de `DeliveryPlan`) ya usa `update`/`update` desde antes — no necesita cambios. Solo `DeliveryPlan#recalculate_load_status!` usaba `update_column`.

**Riesgo de rendimiento aceptado:** en un plan con cientos de items, `mark_all_loaded!` pasa de un único `UPDATE` masivo a N `UPDATE`s individuales. Es una acción manual ocasional de bodega, no un hot path — aceptable.

- [ ] **Step 5: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/models/delivery_plan_test.rb`
Expected: 8 runs, 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/models/delivery_plan.rb test/models/delivery_plan_test.rb
git commit -m "fix: hacer visibles en PaperTrail recalculate_load_status!/mark_all_loaded! de DeliveryPlan"
```

---

### Task 13: `Delivery#mark_all_loaded!`/`#reset_load_status!` → PaperTrail visible

**Files:**
- Modify: `app/models/delivery.rb` (métodos `mark_all_loaded!`, `reset_load_status!`)
- Test: `test/models/delivery_test.rb` (nuevo)

**Interfaces:** ninguna nueva — corrección interna de visibilidad PaperTrail.

- [ ] **Step 1: Escribir los tests**

```ruby
# test/models/delivery_test.rb
require "test_helper"

class DeliveryTest < ActiveSupport::TestCase
  test "mark_all_loaded! leaves a PaperTrail version on each affected item" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(load_status: :unloaded)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      delivery.mark_all_loaded!
    end

    assert_equal "loaded", item.reload.load_status
  end

  test "reset_load_status! leaves a PaperTrail version on each affected item" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(load_status: :loaded)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      delivery.reset_load_status!
    end

    assert_equal "unloaded", item.reload.load_status
  end
end
```

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/models/delivery_test.rb`
Expected: FAIL — `update_all` no genera versiones PaperTrail.

- [ ] **Step 3: Reemplazar `mark_all_loaded!`**

```ruby
  def mark_all_loaded!
    transaction do
      delivery_items
        .where.not(load_status: DeliveryItem.load_statuses[:missing])
        .find_each do |item|
          item.update!(load_status: :loaded, status: :loaded_on_truck)
        end

      recalculate_load_status!
      update_status_based_on_items
    end
  end
```

- [ ] **Step 4: Reemplazar `reset_load_status!`**

```ruby
  def reset_load_status!
    transaction do
      delivery_items.find_each do |item|
        item.update!(load_status: :unloaded)
      end

      recalculate_load_status!
    end
  end
```

- [ ] **Step 5: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/models/delivery_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/models/delivery.rb test/models/delivery_test.rb
git commit -m "fix: hacer visibles en PaperTrail mark_all_loaded!/reset_load_status! de Delivery"
```

---

### Task 14: `DeliveryPlan#update_status_on_driver_change` → PaperTrail visible

**Files:**
- Ya modificado en Task 6 (los dos `update_column` se reemplazaron por `update!` ahí mismo, junto con los callbacks de ciclo de vida).
- Test: `test/models/delivery_plan_test.rb` (agregar test de regresión específico para este método)

**Interfaces:** ninguna nueva.

- [ ] **Step 1: Escribir el test**

```ruby
  test "assigning a driver while all deliveries are confirmed updates status via update! and is visible in PaperTrail" do
    plan = delivery_plans(:one)
    plan.update_columns(status: DeliveryPlan.statuses[:draft])
    plan.deliveries.update_all(status: Delivery.statuses[:in_plan])
    versions_before = PaperTrail::Version.where(item_type: "DeliveryPlan", item_id: plan.id).count

    plan.update!(driver: users(:one))

    assert plan.reload.status_routes_created?
    assert_operator PaperTrail::Version.where(item_type: "DeliveryPlan", item_id: plan.id).count, :>, versions_before
    assert_equal "routes_created", plan.plan_events.last.action
  end
```

(agregar dentro de `DeliveryPlanTest`; usa `update_columns`/`update_all` solo para preparar el estado de la prueba — no es código de producción)

- [ ] **Step 2: Correr el test**

Run: `bin/rails test test/models/delivery_plan_test.rb`
Expected: PASS — este método ya quedó corregido en Task 6, este test es la confirmación de regresión explícita.

- [ ] **Step 3: Commit**

```bash
git add test/models/delivery_plan_test.rb
git commit -m "test: cubrir explícitamente update_status_on_driver_change con PaperTrail visible"
```

---

### Task 15: Mapear enums de `DeliveryPlan`/`DeliveryPlanAssignment` en `ENUM_VALUE_MAPS` (hueco de explicitud encontrado en planning)

**Files:**
- Modify: `app/helpers/audit_logs_helper.rb` (`ENUM_VALUE_MAPS`)
- Test: `test/helpers/audit_logs_helper_test.rb` (nuevo)

**Interfaces:** ninguna nueva — datos adicionales para `format_change_value`.

**Por qué este task no estaba en la spec original:** durante el inventario de archivos para este plan se encontró que `ENUM_VALUE_MAPS` (`app/helpers/audit_logs_helper.rb:50-108`) traduce los enums de `Delivery`, `DeliveryItem`, `Order` y `OrderItem`, pero **no los de `DeliveryPlan` ni `DeliveryPlanAssignment`**. Hoy un diff de PaperTrail en `DeliveryPlan.status` se muestra como `"0 → 3"` en vez de `"Borrador → En progreso"`. Es exactamente el tipo de "algo se nos ha de estar quedando" que motivó este trabajo — se corrige aquí porque es de bajo riesgo y aditivo.

- [ ] **Step 1: Escribir el test (falla porque las claves no existen)**

```ruby
# test/helpers/audit_logs_helper_test.rb
require "test_helper"

class AuditLogsHelperTest < ActionView::TestCase
  include AuditLogsHelper

  test "format_change_value translates DeliveryPlan.status" do
    assert_equal "En progreso", format_change_value(3, "status", "DeliveryPlan")
  end

  test "format_change_value translates DeliveryPlan.load_status" do
    assert_equal "Con faltantes", format_change_value(3, "load_status", "DeliveryPlan")
  end

  test "format_change_value translates DeliveryPlanAssignment.status" do
    assert_equal "En ruta", format_change_value(1, "status", "DeliveryPlanAssignment")
  end
end
```

- [ ] **Step 2: Correr el test para confirmar que falla**

Run: `bin/rails test test/helpers/audit_logs_helper_test.rb`
Expected: FAIL — sin entrada en `ENUM_VALUE_MAPS`, cae al formato genérico y devuelve `"3"`/`"1"` en vez del texto esperado.

- [ ] **Step 3: Agregar las entradas a `ENUM_VALUE_MAPS`**

Dentro del hash `ENUM_VALUE_MAPS` (`app/helpers/audit_logs_helper.rb`), después de la entrada `"OrderItem.status"`, agregar:

```ruby
    "DeliveryPlan.status" => {
      0 => "Borrador",
      1 => "Enviado a logística",
      2 => "Ruta creada",
      3 => "En progreso",
      4 => "Completado",
      5 => "Abortado"
    },
    "DeliveryPlan.load_status" => {
      0 => "Sin cargar",
      1 => "Parcialmente cargado",
      2 => "Completamente cargado",
      3 => "Con faltantes"
    },
    "DeliveryPlanAssignment.status" => {
      0 => "Pendiente",
      1 => "En ruta",
      2 => "Completado",
      3 => "Cancelado"
    }
```

- [ ] **Step 4: Correr el test para confirmar que pasa**

Run: `bin/rails test test/helpers/audit_logs_helper_test.rb`
Expected: 3 runs, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/audit_logs_helper.rb test/helpers/audit_logs_helper_test.rb
git commit -m "fix: traducir enums de DeliveryPlan/DeliveryPlanAssignment en el log de cambios técnicos"
```

---

### Task 16: Conectar `create_summary`/`destroy_summary` al timeline narrativo

**Files:**
- Modify: `app/helpers/timeline_helper.rb` (`timeline_description`)
- Test: agregar al `test/helpers/timeline_helper_test.rb` creado en este mismo task

**Interfaces:**
- Consumes: `create_summary`/`destroy_summary`/`attribute_label`/`format_change_value` (ya existen en `AuditLogsHelper`).
- Produces: ninguna interfaz nueva — corrige el contenido de `timeline_description` para eventos PaperTrail `create`/`destroy`.

- [ ] **Step 1: Escribir el test (falla con el código actual)**

```ruby
# test/helpers/timeline_helper_test.rb
require "test_helper"

class TimelineHelperTest < ActionView::TestCase
  include AuditLogsHelper
  include DeliveryEventsHelper
  include TimelineHelper

  test "timeline_description shows the deleted record's fields for a destroy version, not 'Sin cambios detectados'" do
    item = delivery_items(:one)
    item.update!(status: :delivered)
    item.destroy!

    version = PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id, event: "destroy").last
    entry = TimelineEntry.new(timestamp: version.created_at, source: :paper_trail, record: version)

    refute_equal "Sin cambios detectados", timeline_description(entry)
  end

  test "timeline_description shows the created record's fields for a create version" do
    delivery = deliveries(:one)
    item = delivery.delivery_items.create!(order_item: order_items(:one), quantity_delivered: 2, status: :confirmed)

    version = PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id, event: "create").last
    entry = TimelineEntry.new(timestamp: version.created_at, source: :paper_trail, record: version)

    assert_match(/Confirmado/, timeline_description(entry))
  end
end
```

- [ ] **Step 2: Correr el test para confirmar que falla**

Run: `bin/rails test test/helpers/timeline_helper_test.rb`
Expected: FAIL en el primer test — `version.changeset` es `{}` para un evento `destroy`, así que `timeline_description` devuelve `"Sin cambios detectados"`.

- [ ] **Step 3: Reemplazar `timeline_description` en `app/helpers/timeline_helper.rb`**

```ruby
  def timeline_description(entry, users_by_id: {})
    if entry.delivery_event?
      delivery_event_description(entry.record)
    elsif entry.record.event == "create"
      describe_fields(create_summary(entry.record), entry.record.item_type, "Registro creado")
    elsif entry.record.event == "destroy"
      describe_fields(destroy_summary(entry.record), entry.record.item_type, "Registro eliminado")
    else
      changes = summarize_changes(entry.record, max_keys: 5)
      return "Sin cambios detectados" if changes.blank?

      changes.map do |attr, (before, after)|
        "#{attr.humanize}: #{format_value_detailed(before)} → #{format_value_detailed(after)}"
      end.join(" · ")
    end
  end

  def describe_fields(fields, item_type, fallback)
    return fallback if fields.blank?

    fields.map { |attr, value| "#{attribute_label(attr, item_type)}: #{format_change_value(value, attr, item_type)}" }.join(" · ")
  end
```

- [ ] **Step 4: Correr el test para confirmar que pasa**

Run: `bin/rails test test/helpers/timeline_helper_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/timeline_helper.rb test/helpers/timeline_helper_test.rb
git commit -m "fix: mostrar campos reales en el timeline para eventos create/destroy de PaperTrail"
```

---

### Task 17: `TimelineEntry`/`TimelineGrouper` — soporte para `plan_event`

**Files:**
- Modify: `app/models/timeline_entry.rb` (reemplazo completo)
- Modify: `app/models/timeline_grouper.rb` (reemplazo completo)
- Test: `test/models/timeline_grouper_test.rb` (nuevo)

**Interfaces:**
- Produces: `TimelineEntry#plan_event?`, usado por Tasks 18, 19, 20.
- Produces: `TimelineGrouper.group` agrupa `plan_event` igual que `delivery_event` (mismo actor, ventana de 60s).

- [ ] **Step 1: Escribir el test (falla porque `plan_event?` no existe)**

```ruby
# test/models/timeline_grouper_test.rb
require "test_helper"

class TimelineGrouperTest < ActiveSupport::TestCase
  FakeRecord = Struct.new(:actor_id, :whodunnit)

  test "groups a plan_event with a paper_trail entry from the same actor within the window" do
    now = Time.current
    plan_entry = TimelineEntry.new(timestamp: now, source: :plan_event, record: FakeRecord.new(7, nil))
    pt_entry = TimelineEntry.new(timestamp: now - 10.seconds, source: :paper_trail, record: FakeRecord.new(nil, "7"))

    groups = TimelineGrouper.group([plan_entry, pt_entry])

    assert_equal 1, groups.size
    assert_equal plan_entry, groups.first[:primary]
    assert_equal [pt_entry], groups.first[:secondary]
  end

  test "does not group entries from different actors even within the window" do
    now = Time.current
    plan_entry = TimelineEntry.new(timestamp: now, source: :plan_event, record: FakeRecord.new(7, nil))
    pt_entry = TimelineEntry.new(timestamp: now - 10.seconds, source: :paper_trail, record: FakeRecord.new(nil, "9"))

    groups = TimelineGrouper.group([plan_entry, pt_entry])

    assert_equal 2, groups.size
  end

  test "plan_event? is true only for entries sourced from :plan_event" do
    entry = TimelineEntry.new(timestamp: Time.current, source: :plan_event, record: FakeRecord.new(1, nil))

    assert entry.plan_event?
    refute entry.delivery_event?
    refute entry.paper_trail?
  end
end
```

- [ ] **Step 2: Correr el test para confirmar que falla**

Run: `bin/rails test test/models/timeline_grouper_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'plan_event?'`.

- [ ] **Step 3: Reemplazar `app/models/timeline_entry.rb`**

```ruby
# app/models/timeline_entry.rb
class TimelineEntry
  attr_reader :timestamp, :source, :record

  def initialize(timestamp:, source:, record:)
    @timestamp = timestamp
    @source = source
    @record = record
  end

  def delivery_event? = source == :delivery_event
  def plan_event? = source == :plan_event
  def paper_trail? = source == :paper_trail
  def created_at = timestamp
end
```

- [ ] **Step 4: Reemplazar `app/models/timeline_grouper.rb`**

```ruby
# app/models/timeline_grouper.rb
class TimelineGrouper
  GROUP_WINDOW = 60.seconds

  def self.group(entries)
    return [] if entries.blank?

    sorted = entries.sort_by(&:timestamp).reverse
    groups = []
    current = []

    sorted.each do |entry|
      if current.empty?
        current << entry
      else
        last = current.first
        same_actor = actor_id(last) == actor_id(entry)
        within_window = (last.timestamp - entry.timestamp).abs <= GROUP_WINDOW

        if same_actor && within_window
          current << entry
        else
          groups << finalize(current)
          current = [entry]
        end
      end
    end

    groups << finalize(current) unless current.empty?
    groups
  end

  # ── privado ────────────────────────────────────────────────────────────────

  def self.actor_id(entry)
    entry.paper_trail? ? entry.record.whodunnit.to_s : entry.record.actor_id.to_s
  end
  private_class_method :actor_id

  # Dentro de cada grupo, el evento de negocio (delivery o plan) va primero
  def self.finalize(entries)
    primary = entries.find { |e| e.delivery_event? || e.plan_event? } || entries.first
    rest = entries - [primary]
    {primary: primary, secondary: rest}
  end
  private_class_method :finalize
end
```

- [ ] **Step 5: Correr el test para confirmar que pasa**

Run: `bin/rails test test/models/timeline_grouper_test.rb`
Expected: 3 runs, 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/models/timeline_entry.rb app/models/timeline_grouper.rb test/models/timeline_grouper_test.rb
git commit -m "feat: soportar plan_event en TimelineEntry/TimelineGrouper"
```

---

### Task 18: `TimelineHelper` + `PlanEventsHelper` — renderizar `plan_event`

**Files:**
- Modify: `app/helpers/timeline_helper.rb` (`timeline_icon`/`timeline_color`/`timeline_title`/`timeline_description`/`timeline_actor`/`timeline_source_badge`)
- Create: `app/helpers/plan_events_helper.rb`
- Test: agregar al `test/helpers/timeline_helper_test.rb` (Task 16) y crear `test/helpers/plan_events_helper_test.rb`

**Interfaces:**
- Consumes: `TimelineEntry#plan_event?` (Task 17), `PlanEvent#label/color/icon/actor_name` (Task 3 vía `EventLog`).
- Produces: `plan_event_description(event)`, usado por la vista en Task 19.

- [ ] **Step 1: Escribir los tests (fallan porque `plan_event_description` no existe y las ramas `plan_event?` no están conectadas)**

```ruby
# test/helpers/plan_events_helper_test.rb
require "test_helper"

class PlanEventsHelperTest < ActionView::TestCase
  include PlanEventsHelper

  test "describes a started event" do
    event = PlanEvent.new(action: "started")
    assert_equal "Plan iniciado", plan_event_description(event)
  end

  test "describes a stop_added event using the payload label" do
    event = PlanEvent.new(action: "stop_added", payload: {delivery_id: 5, delivery_label: "Pedido 123 — Calle Falsa 45"}.to_json)
    assert_equal "Parada agregada: Pedido 123 — Calle Falsa 45", plan_event_description(event)
  end

  test "falls back to the delivery id when there is no label in the payload" do
    event = PlanEvent.new(action: "stop_removed", payload: {delivery_id: 5}.to_json)
    assert_equal "Parada quitada: Entrega #5", plan_event_description(event)
  end
end
```

Agregar a `test/helpers/timeline_helper_test.rb` (de Task 16):

```ruby
  test "timeline_icon/color/title delegate to the record for plan_event entries" do
    plan = DeliveryPlan.create!(week: "50", year: 2026, status: :draft)
    event = plan.plan_events.last # "created", generado por el callback de Task 6

    entry = TimelineEntry.new(timestamp: event.created_at, source: :plan_event, record: event)

    assert_equal event.icon, timeline_icon(entry)
    assert_equal event.color, timeline_color(entry)
    assert_equal event.label, timeline_title(entry)
    assert_equal "Sistema", timeline_actor(entry)
  end
```

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/helpers/plan_events_helper_test.rb test/helpers/timeline_helper_test.rb`
Expected: FAIL — `PlanEventsHelper` no existe; `timeline_icon`/etc. tratan cualquier entry que no sea `delivery_event?` como PaperTrail y revientan llamando `entry.record.event` sobre un `PlanEvent` (que no tiene ese método).

- [ ] **Step 3: Crear `app/helpers/plan_events_helper.rb`**

```ruby
# app/helpers/plan_events_helper.rb
module PlanEventsHelper
  def plan_event_description(event)
    data = event.payload_data

    case event.action
    when "created"
      "Plan creado"
    when "sent_to_logistics"
      "Enviado a logística"
    when "routes_created"
      "Ruta creada"
    when "started"
      "Plan iniciado"
    when "finished"
      "Plan finalizado"
    when "aborted"
      "Plan abortado"
    when "stop_added"
      "Parada agregada: #{stop_label(data)}"
    when "stop_removed"
      "Parada quitada: #{stop_label(data)}"
    else
      event.label
    end
  end

  private

  def stop_label(data)
    data["delivery_label"].presence || "Entrega ##{data["delivery_id"]}"
  end
end
```

- [ ] **Step 4: Reemplazar las ramas en `app/helpers/timeline_helper.rb`**

```ruby
  def timeline_icon(entry)
    if entry.delivery_event? || entry.plan_event?
      entry.record.icon
    else
      event_icon(entry.record.event)
    end
  end

  def timeline_color(entry)
    if entry.delivery_event? || entry.plan_event?
      entry.record.color
    else
      event_color(entry.record.event)
    end
  end

  def timeline_title(entry)
    if entry.delivery_event? || entry.plan_event?
      entry.record.label
    else
      case entry.record.event
      when "create" then "Registro creado"
      when "update" then "Actualización técnica"
      when "destroy" then "Registro eliminado"
      else entry.record.event.humanize
      end
    end
  end

  def timeline_description(entry, users_by_id: {})
    if entry.delivery_event?
      delivery_event_description(entry.record)
    elsif entry.plan_event?
      plan_event_description(entry.record)
    elsif entry.record.event == "create"
      describe_fields(create_summary(entry.record), entry.record.item_type, "Registro creado")
    elsif entry.record.event == "destroy"
      describe_fields(destroy_summary(entry.record), entry.record.item_type, "Registro eliminado")
    else
      changes = summarize_changes(entry.record, max_keys: 5)
      return "Sin cambios detectados" if changes.blank?

      changes.map do |attr, (before, after)|
        "#{attr.humanize}: #{format_value_detailed(before)} → #{format_value_detailed(after)}"
      end.join(" · ")
    end
  end

  def describe_fields(fields, item_type, fallback)
    return fallback if fields.blank?

    fields.map { |attr, value| "#{attribute_label(attr, item_type)}: #{format_change_value(value, attr, item_type)}" }.join(" · ")
  end

  def timeline_actor(entry, users_by_id = {})
    if entry.delivery_event? || entry.plan_event?
      entry.record.actor_name
    else
      user_name_for(entry.record, users_by_id)
    end
  end

  def timeline_source_badge(entry)
    if entry.delivery_event? || entry.plan_event?
      content_tag(:span, safe_join([
        content_tag(:i, "", class: "bi bi-activity me-1"),
        "Negocio"
      ]), class: "badge bg-primary-subtle text-primary-emphasis",
        style: "font-size:0.65rem;")
    else
      content_tag(:span, safe_join([
        content_tag(:i, "", class: "bi bi-code-square me-1"),
        "Sistema"
      ]), class: "badge bg-secondary-subtle text-secondary-emphasis",
        style: "font-size:0.65rem;")
    end
  end

  def timeline_context_label(entry, viewing)
    if viewing.is_a?(Delivery) && entry.plan_event?
      plan = entry.record.delivery_plan
      "Plan semana #{plan.week}-#{plan.year}" if plan
    elsif viewing.is_a?(DeliveryPlan) && entry.delivery_event?
      "Entrega ##{entry.record.delivery_id}"
    end
  end
```

(`timeline_critical?`/`CRITICAL_ACTIONS`/`event_icon`/`event_color` quedan igual — sin cambios)

- [ ] **Step 5: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/helpers/plan_events_helper_test.rb test/helpers/timeline_helper_test.rb`
Expected: 7 runs, 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/helpers/plan_events_helper.rb app/helpers/timeline_helper.rb test/helpers/plan_events_helper_test.rb test/helpers/timeline_helper_test.rb
git commit -m "feat: renderizar plan_event en el timeline (icon/color/title/descripción/actor)"
```

---

### Task 19: `AuditLogsController#resource_history` — vínculo bidireccional Delivery ↔ DeliveryPlan

**Files:**
- Modify: `app/controllers/audit_logs_controller.rb` (método `resource_history` + nuevos privados `delivery_events_for`/`plan_events_for`)
- Modify: `app/views/shared/_timeline.html.erb` (badge de contexto)
- Modify: `app/views/audit_logs/resource_history.html.erb` (pasar `viewing:` al partial, generalizar el desglose de "Eventos de negocio")
- Test: `test/controllers/audit_logs_controller_test.rb` (nuevo)

**Interfaces:**
- Consumes: `TimelineEntry#plan_event?` (Task 17), `timeline_context_label` (Task 18).
- Nota sobre la spec: se usa `resource.delivery_plan_assignment` (singular, asociación real) en vez de `delivery_plan_assignments` (plural) — ver "Corrección sobre la spec" al inicio del plan.

- [ ] **Step 1: Escribir los tests (fallan con el código actual)**

```ruby
# test/controllers/audit_logs_controller_test.rb
require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin)
    sign_in @admin
  end

  test "resource_history for a DeliveryPlan includes DeliveryEvent entries from its deliveries" do
    plan = delivery_plans(:one)
    delivery = delivery_plan_assignments(:one).delivery
    DeliveryEvent.record(delivery: delivery, action: "delivered", actor: @admin)

    get resource_history_audit_logs_path(item_type: "DeliveryPlan", item_id: plan.id)

    assert_response :success
    assert_includes @response.body, "Marcada como entregada"
  end

  test "resource_history for a Delivery includes PlanEvent entries from its current plan" do
    assignment = delivery_plan_assignments(:one)
    plan = assignment.delivery_plan
    plan.start!

    get resource_history_audit_logs_path(item_type: "Delivery", item_id: assignment.delivery_id)

    assert_response :success
    assert_includes @response.body, "Plan iniciado"
  end
end
```

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/controllers/audit_logs_controller_test.rb`
Expected: FAIL — el primer test no encuentra "Marcada como entregada" (los `DeliveryEvent` de las deliveries de un plan no se incluyen hoy); el segundo no encuentra "Plan iniciado" (`PlanEvent` no se incluye en el timeline de una Delivery).

- [ ] **Step 3: Reemplazar `resource_history` en `app/controllers/audit_logs_controller.rb`**

```ruby
  def resource_history
    authorize :audit_log, :index?

    @item_type = params[:item_type]
    @item_id = params[:item_id]

    @resource = @item_type.constantize.find_by(id: @item_id)

    # PaperTrail — sin límite de paginación aquí para el merge
    versions_scope = PaperTrail::Version
      .where(item_type: @item_type, item_id: @item_id)
      .order(created_at: :desc)
      .limit(200)

    @events_count = PaperTrail::Version
      .where(item_type: @item_type, item_id: @item_id)
      .group(:event)
      .count

    delivery_events_scope = delivery_events_for(@resource)
    plan_events_scope = plan_events_for(@resource)

    # ── Construir timeline unificado ────────────────────────────────────────
    entries = []

    delivery_events_scope.each do |e|
      entries << TimelineEntry.new(timestamp: e.created_at, source: :delivery_event, record: e)
    end

    plan_events_scope.each do |e|
      entries << TimelineEntry.new(timestamp: e.created_at, source: :plan_event, record: e)
    end

    versions_scope.each do |v|
      entries << TimelineEntry.new(timestamp: v.created_at, source: :paper_trail, record: v)
    end

    # El agrupador devuelve array de { primary:, secondary: }
    @timeline_groups = TimelineGrouper.group(entries)

    # Usuarios para PaperTrail
    user_ids = versions_scope.pluck(:whodunnit).compact.uniq
    @users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }

    # Registros relacionados
    @related_versions = related_versions_for(@resource)

    if @related_versions.present?
      related_user_ids = @related_versions.pluck(:whodunnit).compact.uniq
      @users_by_id.merge!(User.where(id: related_user_ids).index_by { |u| u.id.to_s })
    end
  end
```

- [ ] **Step 4: Agregar los métodos privados nuevos**

Después de `preload_items` en la sección `private` de `app/controllers/audit_logs_controller.rb`, agregar:

```ruby
  # DeliveryEvent propios del recurso, o (si es un DeliveryPlan) los de todas sus entregas.
  def delivery_events_for(resource)
    case resource
    when Delivery
      resource.delivery_events.includes(:actor).recent
    when DeliveryPlan
      DeliveryEvent.where(delivery_id: resource.deliveries.select(:id)).includes(:actor).recent
    else
      DeliveryEvent.none
    end
  end

  # PlanEvent propios del recurso, o (si es una Delivery) los de su plan actual.
  # Nota: Delivery usa has_one :delivery_plan_assignment, así que solo se ve el
  # plan vigente, no el historial de planes pasados (esa relación no se conserva).
  def plan_events_for(resource)
    case resource
    when DeliveryPlan
      resource.plan_events.includes(:actor).recent
    when Delivery
      plan = resource.delivery_plan_assignment&.delivery_plan
      plan ? plan.plan_events.includes(:actor).recent : PlanEvent.none
    else
      PlanEvent.none
    end
  end
```

- [ ] **Step 5: Pasar `viewing:` al partial del timeline**

En `app/views/audit_logs/resource_history.html.erb`, reemplazar:

```erb
      <%= render "shared/timeline",
          timeline_groups: @timeline_groups,
          users_by_id: @users_by_id %>
```

por:

```erb
      <%= render "shared/timeline",
          timeline_groups: @timeline_groups,
          users_by_id: @users_by_id,
          viewing: @resource %>
```

- [ ] **Step 6: Agregar el badge de contexto en `app/views/shared/_timeline.html.erb`**

Reemplazar la línea de locals al inicio:

```erb
<%# locals: timeline_groups, users_by_id %>
```

por:

```erb
<%# locals: timeline_groups, users_by_id, viewing %>
```

Y dentro del header de la tarjeta, reemplazar:

```erb
            <span class="fw-semibold text-dark tc-title">
              <%= timeline_title(primary) %>
            </span>
            <%= timeline_source_badge(primary) %>
```

por:

```erb
            <span class="fw-semibold text-dark tc-title">
              <%= timeline_title(primary) %>
            </span>
            <%= timeline_source_badge(primary) %>
            <% if (context_label = timeline_context_label(primary, local_assigns[:viewing])) %>
              <span class="badge bg-light text-muted border"><%= context_label %></span>
            <% end %>
```

- [ ] **Step 7: Generalizar el desglose de "Eventos de negocio" en `app/views/audit_logs/resource_history.html.erb`**

Reemplazar:

```erb
          <% business_groups = @timeline_groups.select { |g| g[:primary].delivery_event? } %>
          <% if business_groups.any? %>
            <p class="text-muted small fw-semibold mb-2">Eventos de negocio</p>
            <% actions_count = business_groups.group_by { |g| g[:primary].record.action }
                                              .transform_values(&:size) %>
            <% total_ev = business_groups.size %>
            <% DeliveryEvent::ACTION_LABELS.each do |action, label| %>
              <% count = actions_count[action] || 0 %>
              <% next if count.zero? %>
              <div class="mb-2">
                <div class="d-flex justify-content-between align-items-center mb-1">
                  <span class="small text-<%= DeliveryEvent::ACTION_COLORS[action] || 'secondary' %>">
                    <i class="bi <%= DeliveryEvent::ACTION_ICONS[action] || 'bi-circle' %> me-1"></i>
                    <%= label %>
                  </span>
                  <strong class="small"><%= count %></strong>
                </div>
                <div class="progress rounded-pill" style="height:5px;">
                  <div class="progress-bar bg-<%= DeliveryEvent::ACTION_COLORS[action] || 'secondary' %> rounded-pill"
                       style="width:<%= total_ev.zero? ? 0 : (count * 100.0 / total_ev).round %>%">
                  </div>
                </div>
              </div>
            <% end %>
            <hr class="my-3">
          <% end %>
```

por:

```erb
          <% business_groups = @timeline_groups.select { |g| g[:primary].delivery_event? || g[:primary].plan_event? } %>
          <% if business_groups.any? %>
            <p class="text-muted small fw-semibold mb-2">Eventos de negocio</p>
            <% total_ev = business_groups.size %>
            <% business_groups.group_by { |g| g[:primary].record.action }.each do |action, groups| %>
              <% sample = groups.first[:primary].record %>
              <% count = groups.size %>
              <div class="mb-2">
                <div class="d-flex justify-content-between align-items-center mb-1">
                  <span class="small text-<%= sample.color %>">
                    <i class="bi <%= sample.icon %> me-1"></i>
                    <%= sample.label %>
                  </span>
                  <strong class="small"><%= count %></strong>
                </div>
                <div class="progress rounded-pill" style="height:5px;">
                  <div class="progress-bar bg-<%= sample.color %> rounded-pill"
                       style="width:<%= total_ev.zero? ? 0 : (count * 100.0 / total_ev).round %>%">
                  </div>
                </div>
              </div>
            <% end %>
            <hr class="my-3">
          <% end %>
```

- [ ] **Step 8: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/controllers/audit_logs_controller_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [ ] **Step 9: Verificación manual en navegador**

Run: `bin/rails server` (o el comando de arranque habitual del proyecto)
1. Iniciar sesión como un usuario con `admin?`/`manager?`/`logistics`/`production_manager`.
2. Ir a `/audit_logs`, hacer clic en el ícono de historial de cualquier entrega que pertenezca a un plan.
3. Confirmar que aparece un badge "Plan semana X-YYYY" en los eventos que vienen del plan.
4. Repetir desde la vista de historial de un `DeliveryPlan` y confirmar el badge "Entrega #N" en los eventos que vienen de sus entregas.
Expected: ambos badges visibles, sin errores 500 en consola/log.

- [ ] **Step 10: Commit**

```bash
git add app/controllers/audit_logs_controller.rb app/views/shared/_timeline.html.erb app/views/audit_logs/resource_history.html.erb test/controllers/audit_logs_controller_test.rb
git commit -m "feat: timeline bidireccional Delivery <-> DeliveryPlan en resource_history"
```

---

### Task 20: `AuditLogsController#index` — filtros por plan/semana-año/chofer + feed combinado

**Files:**
- Modify: `app/controllers/audit_logs_controller.rb` (método `index`)
- Modify: `app/views/audit_logs/index.html.erb` (filtros nuevos + filas polimórficas)
- Modify: `app/helpers/audit_logs_helper.rb` (helpers `audit_event_description`/`audit_event_resource_link`)
- Test: agregar a `test/controllers/audit_logs_controller_test.rb` (Task 19)

**Interfaces:** ninguna nueva hacia otras tareas — es la última pieza del plan.

- [ ] **Step 1: Escribir los tests (fallan con el código actual)**

```ruby
  test "index events tab includes both DeliveryEvent and PlanEvent in one combined feed" do
    delivery = delivery_plan_assignments(:one).delivery
    DeliveryEvent.record(delivery: delivery, action: "delivered", actor: @admin)
    delivery_plans(:one).abort!

    get audit_logs_path(tab: "events")

    assert_response :success
    assert_includes @response.body, "Marcada como entregada"
    assert_includes @response.body, "Abortado"
  end

  test "index events tab filters by delivery_plan_id" do
    other_plan = DeliveryPlan.create!(week: "45", year: 2026, status: :draft)

    get audit_logs_path(tab: "events", delivery_plan_id: other_plan.id)

    assert_response :success
    assert_includes @response.body, "Plan creado"
    refute_includes @response.body, "Abortado"
  end
```

(agregar dentro de `AuditLogsControllerTest`, Task 19)

- [ ] **Step 2: Correr los tests para confirmar que fallan**

Run: `bin/rails test test/controllers/audit_logs_controller_test.rb`
Expected: FAIL — el feed de "events" hoy solo trae `DeliveryEvent`, y no existe el filtro `delivery_plan_id`.

- [ ] **Step 3: Reemplazar el método `index` en `app/controllers/audit_logs_controller.rb`**

```ruby
  def index
    authorize :audit_log, :index?

    @active_tab = params[:tab].presence_in(%w[events versions]) || "events"

    # Eventos de negocio — DeliveryEvent + PlanEvent combinados en un solo feed
    events_scope = DeliveryEvent.includes(:actor, :delivery).recent
    plan_events_scope = PlanEvent.includes(:actor, :delivery_plan).recent

    if params[:delivery_id].present?
      events_scope = events_scope.where(delivery_id: params[:delivery_id])
      plan_events_scope = plan_events_scope.none
    end
    if params[:event_action].present?
      events_scope = events_scope.for_action(params[:event_action])
      plan_events_scope = plan_events_scope.for_action(params[:event_action])
    end
    if params[:event_actor_id].present?
      events_scope = events_scope.by_actor(params[:event_actor_id])
      plan_events_scope = plan_events_scope.by_actor(params[:event_actor_id])
    end
    if params[:event_from].present?
      from = params[:event_from].to_date.beginning_of_day
      events_scope = events_scope.where("delivery_events.created_at >= ?", from)
      plan_events_scope = plan_events_scope.where("plan_events.created_at >= ?", from)
    end
    if params[:event_to].present?
      to = params[:event_to].to_date.end_of_day
      events_scope = events_scope.where("delivery_events.created_at <= ?", to)
      plan_events_scope = plan_events_scope.where("plan_events.created_at <= ?", to)
    end
    if params[:delivery_plan_id].present?
      events_scope = events_scope.joins(delivery: {delivery_plan_assignment: :delivery_plan})
        .where(delivery_plans: {id: params[:delivery_plan_id]})
      plan_events_scope = plan_events_scope.where(delivery_plan_id: params[:delivery_plan_id])
    end
    if params[:plan_week].present? || params[:plan_year].present?
      plan_conditions = {}
      plan_conditions[:week] = params[:plan_week] if params[:plan_week].present?
      plan_conditions[:year] = params[:plan_year] if params[:plan_year].present?

      events_scope = events_scope.joins(delivery: {delivery_plan_assignment: :delivery_plan})
        .where(delivery_plans: plan_conditions)
      plan_events_scope = plan_events_scope.joins(:delivery_plan).where(delivery_plans: plan_conditions)
    end
    if params[:driver_id].present?
      events_scope = events_scope.joins(delivery: {delivery_plan_assignment: :delivery_plan})
        .where(delivery_plans: {driver_id: params[:driver_id]})
      plan_events_scope = plan_events_scope.joins(:delivery_plan).where(delivery_plans: {driver_id: params[:driver_id]})
    end

    combined = (events_scope.to_a + plan_events_scope.to_a).sort_by(&:created_at).reverse
    @delivery_events = Kaminari.paginate_array(combined).page(params[:page]).per(50)
    @total_events = DeliveryEvent.count + PlanEvent.count

    # Cambios técnicos
    @q = PaperTrail::Version.ransack(params[:q])
    @q.sorts = "created_at desc" if @q.sorts.empty?

    @versions = @q.result.page(params[:page]).per(50)
    user_ids = @versions.pluck(:whodunnit).compact.uniq
    @users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }
    @items_cache = preload_items(@versions)
    @item_types = PaperTrail::Version.distinct.pluck(:item_type).compact.sort
  end
```

- [ ] **Step 4: Agregar helpers polimórficos en `app/helpers/audit_logs_helper.rb`**

Al final del módulo, antes del `end` final, agregar:

```ruby
  # ── Eventos combinados (DeliveryEvent + PlanEvent) ──────────────────────────

  def audit_event_description(event)
    event.is_a?(PlanEvent) ? plan_event_description(event) : delivery_event_description(event)
  end

  def audit_event_resource_link(event)
    if event.is_a?(PlanEvent)
      {item_type: "DeliveryPlan", item_id: event.delivery_plan_id, label: "Plan ##{event.delivery_plan_id}"}
    else
      {item_type: "Delivery", item_id: event.delivery_id, label: "##{event.delivery_id}"}
    end
  end
```

- [ ] **Step 5: Actualizar `app/views/audit_logs/index.html.erb`**

Reemplazar la fila de la tabla de eventos (dentro de `<% @delivery_events.each do |event| %>`):

```erb
                  <td class="py-3">
                    <%= link_to "##{event.delivery_id}",
                        resource_history_audit_logs_path(item_type: "Delivery", item_id: event.delivery_id),
                        class: "small fw-semibold text-decoration-none text-primary" %>
                  </td>
                  <td class="py-3">
                    <span class="badge" style="<%= delivery_event_badge_style(event) %>; font-size:0.72rem;">
                      <i class="bi <%= event.icon %> me-1"></i><%= event.label %>
                    </span>
                  </td>
                  <td class="py-3">
                    <span class="small"><%= delivery_event_description(event) %></span>
                  </td>
```

por:

```erb
                  <% link_data = audit_event_resource_link(event) %>
                  <td class="py-3">
                    <%= link_to link_data[:label],
                        resource_history_audit_logs_path(item_type: link_data[:item_type], item_id: link_data[:item_id]),
                        class: "small fw-semibold text-decoration-none text-primary" %>
                  </td>
                  <td class="py-3">
                    <span class="badge" style="<%= delivery_event_badge_style(event) %>; font-size:0.72rem;">
                      <i class="bi <%= event.icon %> me-1"></i><%= event.label %>
                    </span>
                  </td>
                  <td class="py-3">
                    <span class="small"><%= audit_event_description(event) %></span>
                  </td>
```

Y la columna del botón "Ver historial":

```erb
                  <td class="py-3 text-center pe-3">
                    <%= link_to resource_history_audit_logs_path(item_type: "Delivery", item_id: event.delivery_id),
                        class: "btn btn-sm btn-outline-secondary",
                        title: "Ver historial",
                        data: { bs_toggle: "tooltip" } do %>
                      <i class="bi bi-clock-history"></i>
                    <% end %>
                  </td>
```

por:

```erb
                  <td class="py-3 text-center pe-3">
                    <%= link_to resource_history_audit_logs_path(item_type: link_data[:item_type], item_id: link_data[:item_id]),
                        class: "btn btn-sm btn-outline-secondary",
                        title: "Ver historial",
                        data: { bs_toggle: "tooltip" } do %>
                      <i class="bi bi-clock-history"></i>
                    <% end %>
                  </td>
```

Y agregar 3 campos de filtro nuevos al formulario (dentro del `form_with` de la tab "events", después del campo `event_to`):

```erb
            <div class="col-12 col-md-2">
              <%= f.label :delivery_plan_id, class: "form-label small fw-semibold text-muted mb-1" do %>
                <i class="bi bi-calendar3 me-1"></i>Plan #
              <% end %>
              <%= f.text_field :delivery_plan_id, value: params[:delivery_plan_id],
                  class: "form-control form-control-sm", placeholder: "Ej: 42" %>
            </div>
            <div class="col-6 col-md-1">
              <%= f.label :plan_week, "Semana", class: "form-label small fw-semibold text-muted mb-1" %>
              <%= f.text_field :plan_week, value: params[:plan_week], class: "form-control form-control-sm" %>
            </div>
            <div class="col-6 col-md-1">
              <%= f.label :plan_year, "Año", class: "form-label small fw-semibold text-muted mb-1" %>
              <%= f.text_field :plan_year, value: params[:plan_year], class: "form-control form-control-sm" %>
            </div>
            <div class="col-12 col-md-2">
              <%= f.label :driver_id, class: "form-label small fw-semibold text-muted mb-1" do %>
                <i class="bi bi-person-badge me-1"></i>Chofer
              <% end %>
              <%= f.select :driver_id,
                  options_for_select([["Todos", ""]] + User.order(:name).pluck(:name, :id), params[:driver_id]),
                  {}, class: "form-select form-select-sm" %>
            </div>
```

- [ ] **Step 6: Correr los tests para confirmar que pasan**

Run: `bin/rails test test/controllers/audit_logs_controller_test.rb`
Expected: 4 runs, 0 failures, 0 errors.

- [ ] **Step 7: Verificación manual en navegador**

Run: `bin/rails server`
1. Ir a `/audit_logs`, confirmar que el feed mezcla filas de entregas y de planes (íconos/colores distintos) ordenadas por fecha.
2. Filtrar por un `delivery_plan_id` existente y confirmar que solo aparecen eventos de ese plan.
3. Filtrar por semana/año y por chofer y confirmar que el feed se acota correctamente.
Expected: sin errores 500, paginación funcional con el array combinado.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/audit_logs_controller.rb app/helpers/audit_logs_helper.rb app/views/audit_logs/index.html.erb test/controllers/audit_logs_controller_test.rb
git commit -m "feat: feed combinado DeliveryEvent+PlanEvent con filtros por plan/semana-año/chofer"
```

---

## Regresión final

- [ ] **Step 1: Correr toda la suite de tests del proyecto**

Run: `bin/rails test`
Expected: 0 failures, 0 errors. Si algo en `test/controllers/delivery_plans_controller_test.rb` o `test/controllers/production/` falla por los cambios de `update_column`→`update!` (callbacks adicionales disparándose, broadcasts Turbo nuevos), investigar y corregir antes de continuar — no se debe mergear con regresiones.

- [ ] **Step 2: Confirmar que `graphify update .` refleja los modelos nuevos** (regla del proyecto en `CLAUDE.md`)

Run: `graphify update .`
Expected: el grafo incorpora `PlanEvent`, `AuditActor`, `EventLog` y las nuevas relaciones sin errores.

---

## Self-Review (completado durante la escritura de este plan)

**1. Cobertura de la spec:** las 9 secciones de `docs/superpowers/specs/2026-06-18-modulo-auditoria-deliveries-y-planes-design.md` tienen tarea(s) correspondientes — arquitectura (Tasks 2-4), modelo de datos (Task 1, 3), instrumentación (Tasks 6-14), timeline bidireccional (Tasks 16-19), filtros (Task 20), manejo de errores (verificado en cada test de `record`/`record_event`), testing (cada task incluye los suyos). Se agregó un Task 15 fuera de la spec original (mapas de enum faltantes) — discrepancia documentada en el propio task.

**2. Placeholders:** ninguno — cada step tiene código completo, comandos exactos y output esperado.

**3. Consistencia de tipos/nombres:** `PlanEvent.record(delivery_plan:, action:, actor:, payload:)` se usa con la misma firma en Tasks 6, 7. `DeliveryEvent.record(delivery:, action:, actor:, payload:)` se usa igual en Tasks 8, 9, 10. `AuditActor.current` no recibe argumentos en ningún call site. `timeline_context_label(entry, viewing)` y `audit_event_resource_link(event)` se definen una vez (Tasks 18, 20) y no se renombran después.

**4. Corrección sobre la spec aprobada:** documentada al inicio del plan (Global Constraints) — `has_one` vs `has_many` en `Delivery#delivery_plan_assignment`. No requiere reabrir el spec; es un ajuste de implementación fiel a la intención original.

---

**Plan completo y guardado en `docs/superpowers/plans/2026-06-18-modulo-auditoria-deliveries-y-planes.md`.**

Dos opciones de ejecución:

1. **Subagent-Driven (recomendado)** — despacho un subagente nuevo por tarea, con revisión entre tareas e iteración rápida.
2. **Ejecución en línea** — ejecuto las tareas en esta misma sesión con checkpoints de revisión por bloque.

¿Cuál prefieres?
