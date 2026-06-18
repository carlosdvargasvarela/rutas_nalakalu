# Mejora del módulo de auditoría: Deliveries + Delivery Plans

**Fecha:** 2026-06-18
**Alcance:** Capa de auditoría/eventos de negocio para `Delivery`, `DeliveryItem`, `DeliveryPlan` y `DeliveryPlanAssignment`. No incluye `Order`/`OrderItem` salvo lo que ya existe hoy.

---

## 1. Contexto y problema

Hoy la auditoría combina dos fuentes:

- **PaperTrail** (`has_paper_trail`, tabla `versions`): diffs crudos de columnas para 13 modelos (`Client`, `Order`, `OrderItem`, `Delivery`, `DeliveryItem`, `DeliveryAddress`, `DeliveryPlan`, `DeliveryPlanAssignment`, `Seller`, `User`, `Notification`, `MaintenanceWindow`, `CrewMember`), sin metadata adicional (sin IP, sin razón).
- **`DeliveryEvent`** (tabla `delivery_events`): log de negocio con narrativa (acción, actor, payload JSON, label/color/icono), pero **exclusivo de `Delivery`** — no existe equivalente para `DeliveryPlan`.

`AuditLogsController` expone esto en dos tabs ("events"/"versions") y una vista `resource_history` que mezcla `DeliveryEvent` + `PaperTrail::Version` en un timeline único vía `TimelineGrouper`, pero solo para el recurso que se está viendo — sin vínculo entre una entrega y el plan al que pertenece.

### Hallazgos concretos (root cause)

1. **El timeline ignora datos que ya existen.** Para eventos `destroy` de PaperTrail, `version.changeset` siempre es `{}` (PaperTrail solo llena `object_changes` en create/update, no en destroy — ver `paper_trail-16.0.0/lib/paper_trail/version_concern.rb:317`). El timeline narrativo (`_timeline.html.erb` vía `TimelineHelper#timeline_description`) solo sabe leer `changeset`, así que un registro eliminado se muestra como "Sin cambios detectados" aunque sus campos completos están en `version.object`. Los helpers `create_summary`/`destroy_summary` (`app/helpers/audit_logs_helper.rb:131,146`) ya saben extraer eso — se usan en la tabla "versions" y en `_related_version_compact.html.erb`, pero nunca se conectaron al timeline narrativo.
2. **`DeliveryPlan` no tiene narrativa de negocio.** Solo PaperTrail (diffs de columna: `status: 0 → 3`). No hay registro de quién inició/abortó/finalizó un plan, ni de qué entregas se agregaron/quitaron.
3. **~20 transiciones de estado usan `update_column`/`update_all`, que se saltan PaperTrail por completo** (no hay callbacks → no hay versión). Ejemplos confirmados: `DeliveryPlanAssignment#start!/complete!/mark_as_failed!`, `DeliveryPlan#recalculate_load_status!`/`mark_all_loaded!`/`update_status_on_driver_change`, `Delivery#recalculate_load_status!`/`mark_all_loaded!`/`reset_load_status!`, `DeliveryFailureService#mark_as_failed!`. Estas transiciones no dejan rastro en ningún lado hoy.

---

## 2. Decisión de arquitectura

**Opción elegida: modelo `PlanEvent` paralelo a `DeliveryEvent`**, compartiendo un concern `EventLog`, sin migrar la tabla `delivery_events` existente ni tocar sus ~25 puntos de llamada actuales.

Se descartó unificar en una tabla polimórfica única (`AuditEvent`) por requerir migrar datos de producción y reescribir todos los call sites existentes para un beneficio (soporte futuro a más tipos de recurso) que no se pidió.

---

## 3. Modelo de datos

### Tabla nueva `plan_events`
```
delivery_plan_id  bigint, not null, index
action            string, not null, index
actor_id          bigint, nullable (FK a users)
payload           text
created_at        datetime, not null, index
```

### Concern compartido `app/models/concerns/event_log.rb`
Extraído de `DeliveryEvent` (sin cambiar su comportamiento público):
- Validación `action` presente, scopes `recent`/`for_action`/`by_actor`.
- `payload_data` (deserializa JSON, rescata `JSON::ParserError`).
- `label`/`color`/`icon`/`actor_name`, leyendo `ACTION_LABELS`/`ACTION_COLORS`/`ACTION_ICONS` definidos en cada clase incluyente.
- `record_event(attrs)` — factory privada que hace `create!` con `created_at: Time.current` y rescata cualquier error (logueando, sin relanzar) — igual que el `rescue` actual de `DeliveryEvent.record`.

`DeliveryEvent` pasa a `include EventLog` y mantiene su `self.record(delivery:, action:, actor: nil, payload: {})` tal cual (cero cambios para los call sites existentes).

`PlanEvent` nuevo:
```ruby
class PlanEvent < ApplicationRecord
  include EventLog
  belongs_to :delivery_plan
  belongs_to :actor, class_name: "User", optional: true
  validates :delivery_plan_id, presence: true

  ACTIONS = %w[created sent_to_logistics routes_created started finished aborted
               stop_added stop_removed]

  ACTION_LABELS = {
    "created"           => "Plan creado",
    "sent_to_logistics"  => "Enviado a logística",
    "routes_created"     => "Ruta creada",
    "started"            => "Iniciado",
    "finished"           => "Finalizado",
    "aborted"            => "Abortado",
    "stop_added"         => "Parada agregada",
    "stop_removed"       => "Parada quitada"
  }.freeze

  ACTION_COLORS = {
    "created"           => "success",
    "sent_to_logistics"  => "primary",
    "routes_created"     => "primary",
    "started"            => "info",
    "finished"           => "success",
    "aborted"            => "danger",
    "stop_added"         => "secondary",
    "stop_removed"       => "warning"
  }.freeze

  ACTION_ICONS = {
    "created"           => "bi-plus-circle",
    "sent_to_logistics"  => "bi-send",
    "routes_created"     => "bi-signpost-2",
    "started"            => "bi-play-circle",
    "finished"           => "bi-check-circle",
    "aborted"            => "bi-x-circle",
    "stop_added"         => "bi-pin-map",
    "stop_removed"       => "bi-pin-map-fill"
  }.freeze

  def self.record(delivery_plan:, action:, actor: nil, payload: {})
    record_event(delivery_plan: delivery_plan, action: action, actor: actor, payload: payload.to_json)
  end
end
```

### Resolución de actor sin `current_user` explícito
Nuevo módulo `AuditActor` en `app/models/audit_actor.rb` (mismo nivel que `TimelineGrouper`/`TimelineEntry`, que tampoco son ActiveRecord pero viven en `app/models/`):
```ruby
module AuditActor
  def self.current
    User.find_by(id: PaperTrail.request.whodunnit)
  end
end
```
Reutiliza el mismo mecanismo que ya alimenta PaperTrail vía `set_paper_trail_whodunnit` (`ApplicationController`). Se usa solo en los puntos de instrumentación nuevos que viven dentro de modelos/servicios sin acceso directo a `current_user` (ver sección 4). Los ~25 call sites existentes de `DeliveryEvent.record` en controladores siguen pasando `actor: current_user` explícito, sin cambios.

### Borrado en cascada
`DeliveryPlan` agrega `has_many :plan_events, dependent: :destroy` — al eliminar un plan (solo permitido en `draft`/`sent_to_logistics`/`routes_created`, ver `ensure_deletable`) no quedan eventos huérfanos.

---

## 4. Puntos de instrumentación

### Creación del plan → `PlanEvent`
`DeliveryPlan` agrega `after_create :record_created_event`, que genera `PlanEvent.record(delivery_plan: self, action: "created", actor: AuditActor.current)`.

### Ciclo de vida del plan → `PlanEvent`
`DeliveryPlan#start!`, `#finish!`, `#abort!`, `#send_to_logistics!` y el callback `update_status_on_driver_change` ya son los únicos puntos donde cambia `status`. Se centraliza con un callback:
```ruby
after_update :record_status_change_event, if: :saved_change_to_status?
```
que mapea el nuevo `status` a la acción de `PlanEvent` correspondiente (`in_progress` → `started`, `completed` → `finished`, `aborted` → `aborted`, `routes_created` → `routes_created`, `sent_to_logistics` → `sent_to_logistics`), con `actor: AuditActor.current`. Esto cubre **todos** los caminos que cambian `status`, incluyendo ediciones directas vía formulario — no solo los métodos `start!`/`finish!`/`abort!`.

### Paradas agregadas/quitadas → `PlanEvent`
`DeliveryPlanAssignment` agrega:
```ruby
after_create  :record_stop_added
after_destroy :record_stop_removed
```
Payload incluye `delivery_id` y un texto descriptivo (número de pedido / dirección) para que el evento sea legible aunque la entrega luego se mueva de plan.

### Transiciones invisibles → PaperTrail visible + eventos de negocio puntuales

| Ubicación | Cambio |
|---|---|
| `DeliveryPlanAssignment#start!` | `delivery.update_column` → `delivery.update!`; items `update_all` → `update!` por registro; agregar `DeliveryEvent.record(delivery:, action: "route_started", actor: AuditActor.current, payload: {delivery_plan_id:, stop_order:})` |
| `DeliveryPlanAssignment#complete!` | Agregar `DeliveryEvent.record(delivery:, action: "delivered", actor: AuditActor.current, payload: {via: "plan_assignment"})` después de `mark_as_delivered!` |
| `DeliveryPlanAssignment#mark_as_failed!` / `DeliveryFailureService` | Items `update_all` → `update!` por registro; agregar `DeliveryEvent.record(delivery:, action: "failed", actor: failed_by || AuditActor.current, payload: {reason:, new_delivery_id:})` (acción nueva en `DeliveryEvent::ACTIONS`) |
| `DeliveryPlanAssignment#change_deliveries_statuses` / `#revert_statuses` | `update_column`/`update_all` → `update!` por registro. Sin evento de negocio propio (la narrativa ya la cubre `stop_added`/`stop_removed`) |
| `DeliveryPlan#recalculate_load_status!`, `#mark_all_loaded!` | `update_column`/`update_all` → `update!` por registro. Sin evento de negocio propio (derivado) |
| `Delivery#recalculate_load_status!`, `#mark_all_loaded!`, `#reset_load_status!` | `update_all` en items → `update!` por registro |
| `DeliveryPlan#update_status_on_driver_change` | `update_column` → `update!` (ya queda narrado por el callback de ciclo de vida de la sección anterior) |

**Fuera de alcance explícitamente:** `OrderItem#update_column` (`order_item.rb:56,58`) — pertenece al dominio de `Order`, no se pidió y no se toca.

**Riesgo de rendimiento aceptado:** convertir `update_all` a `update!` por registro en `DeliveryPlan#mark_all_loaded!` y `Delivery#mark_all_loaded!` puede tocar decenas/cientos de filas en una sola acción manual de bodega — aceptable porque no es un hot path ni una operación de alta frecuencia.

---

## 5. Timeline unificado bidireccional

### Arreglo del hueco create/destroy
`TimelineHelper#timeline_description` (rama "no es delivery_event") pasa a usar `create_summary(version)`/`destroy_summary(version)` cuando `version.event` es `"create"`/`"destroy"` respectivamente, en vez de `summarize_changes` (que solo sirve para `"update"`).

### Vínculo bidireccional en `AuditLogsController#resource_history`
- `@resource.is_a?(Delivery)` → además de `@resource.delivery_events`, se agregan los `PlanEvent` de los planes a los que la entrega perteneció (`delivery.delivery_plan_assignments.includes(:delivery_plan)` → `delivery_plan.plan_events`), como `TimelineEntry` con `source: :plan_event`.
- `@resource.is_a?(DeliveryPlan)` → además de `@resource.plan_events`, se agregan los `DeliveryEvent` de todas sus deliveries (`plan.deliveries.includes(:delivery_events)`).

### Cambios mecánicos de soporte
- `TimelineEntry`: nuevo `source: :plan_event`, predicado `plan_event?`.
- `TimelineGrouper#actor_id`: invertir la condición actual (que asume "si no es delivery_event, es paper_trail") a `entry.paper_trail? ? entry.record.whodunnit.to_s : entry.record.actor_id.to_s`, para que `plan_event` agrupe igual que `delivery_event`.
- `TimelineHelper` (`timeline_icon`/`timeline_color`/`timeline_title`/`timeline_actor`/`timeline_critical?`): tratar `entry.plan_event?` igual que `entry.delivery_event?` (ambos exponen `label`/`color`/`icon`/`actor_name` vía `EventLog`).
- Nuevo `app/helpers/plan_events_helper.rb#plan_event_description`, análogo a `delivery_event_description`, con texto por acción (`started` → "Plan iniciado", `stop_added` → "Parada agregada: Entrega #X — <dirección>", etc.)
- `_timeline.html.erb`: badge de contexto cuando la entrada viene del "otro" recurso (ej. "Plan semana 25-2026" dentro del timeline de una entrega; "Entrega #1234" dentro del timeline de un plan).

---

## 6. Filtros nuevos en el índice

`AuditLogsController#index`, tab "events", agrega filtros: plan específico (`params[:delivery_plan_id]`), semana/año de plan (`params[:plan_week]`/`params[:plan_year]`), chofer (`params[:driver_id]`).

Como ahora hay dos tablas, cada filtro se aplica a ambas consultas:
- `PlanEvent`: `joins(:delivery_plan)` cuando el filtro lo requiere.
- `DeliveryEvent`: `joins(delivery: {delivery_plan_assignments: :delivery_plan})` (con `.distinct` para evitar duplicados si una entrega tuvo más de un assignment histórico).

Los dos result sets filtrados se combinan en un array Ruby, se ordenan por `created_at desc`, y se paginan con `Kaminari.paginate_array(combined).page(params[:page]).per(50)` — un solo feed cronológico mezclado, igual que ya se pidió para `resource_history`.

---

## 7. Manejo de errores

- `PlanEvent.record` nunca bloquea la operación de negocio si falla (rescata y loguea — mismo comportamiento que `DeliveryEvent.record` hoy).
- Los callbacks nuevos (`after_update`, `after_create`, `after_destroy`) llaman a `record_event`, que ya no relanza — un fallo al loguear un evento no puede tumbar un `start!`/`finish!`/etc.
- `has_many :plan_events, dependent: :destroy` evita huérfanos al borrar un plan.

---

## 8. Testing

- **Modelo `EventLog`/`PlanEvent`/`DeliveryEvent`**: validaciones, scopes, `record`, `label`/`color`/`icon`, `payload_data` con JSON inválido.
- **`DeliveryPlan`**: cada transición de `status` genera el `PlanEvent` correcto; `AuditActor.current` sin request (job/rake) → actor nulo → `actor_name` cae a "Sistema".
- **`DeliveryPlanAssignment`**: `start!`/`complete!`/`mark_as_failed!` generan el `DeliveryEvent` esperado; create/destroy generan `stop_added`/`stop_removed`.
- **`AuditLogsController`**: `resource_history` mezcla correctamente en ambas direcciones (Delivery↔Plan); `index` filtra por plan/semana-año/chofer y pagina el feed combinado.
- **Regresión**: tests existentes de `mark_all_loaded!`, `start!`, `complete!`, `mark_as_failed!`, `reopen!`, etc. siguen pasando tras cambiar `update_all`/`update_column` a `update!` por registro.

---

## 9. No-goals (explícitos)

- No se migra ni renombra la tabla `versions`/`delivery_events` existente.
- No se agrega exportación a PDF/Excel ni endpoint API para terceros (puede ser una fase futura).
- No se instrumenta `Order`/`OrderItem` más allá de lo que ya existe.
- No se agregan eventos de negocio dedicados para recálculos derivados de `load_status` (quedan cubiertos por PaperTrail, no por narrativa de negocio).
