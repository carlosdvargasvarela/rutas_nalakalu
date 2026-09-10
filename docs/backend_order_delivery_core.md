# Módulo: Order / Delivery Core

Documenta el núcleo de dominio del backend: `Order`, `OrderItem`, `Delivery`, `DeliveryItem`. Es el módulo con más god nodes del grafo (`Order` 157 edges, `Delivery` 87 edges) — todo lo demás (plans, notificaciones, reportes) cuelga de aquí.

## Jerarquía

```
Order (belongs_to client, seller)
 └─ has_many order_items
     └─ has_many delivery_items
         └─ belongs_to delivery
Order └─ has_many deliveries (a través de delivery_items → delivery)
Delivery belongs_to order, delivery_address
 └─ has_many delivery_items
 └─ has_one delivery_plan_assignment → delivery_plan
 └─ has_one delivery_group_membership → delivery_group
```

Un `Order` puede generar varias `Delivery` (entregas parciales/reprogramaciones). Cada `Delivery` agrupa `DeliveryItem`s que apuntan a `OrderItem`s del mismo pedido.

## Máquinas de estado

Tres enums de status independientes, todos derivados unos de otros en cascada ascendente (item → delivery/order_item → order):

- **`OrderItem#status`**: `in_production → ready → delivered` (+ `cancelled`, `missing`)
- **`DeliveryItem#status`**: `pending → confirmed → in_plan → in_route → delivered` (+ `rescheduled`, `cancelled`, `failed`, `loaded_on_truck`, `warehousing`)
- **`Delivery#status`**: `scheduled → ready_to_deliver → in_plan → in_route → delivered` (+ `rescheduled`, `cancelled`, `archived`, `failed`, `loaded_on_truck`, `warehousing`)
- **`Order#status`**: `in_production → ready_for_delivery → delivered` (+ `rescheduled`, `cancelled`)

### Propagación (callbacks en cadena)

```
DeliveryItem#after_update :update_order_item_status
  → OrderItem#update_status_based_on_deliveries → OrderItem#update_order_status
    → Order#check_and_update_status!

DeliveryItem#after_commit :recalculate_delivery_status
  → Delivery#update_status_based_on_items (calculate_delivery_status, ver delivery.rb:592)
```

`Delivery#calculate_delivery_status` es la lógica más compleja del módulo: decide el status agregado de la entrega en base al conjunto de status de sus items, con reglas explícitas para "todos terminales iguales", "terminales mezclados" (prioridad delivered > failed > cancelled > rescheduled) y "activos" (manda el ítem menos avanzado). Está bien documentada in-line (delivery.rb:568-591) — no hace falta repetirla aquí, léanla ahí si se toca esa lógica.

### Broadcasting en tiempo real

`Delivery` y `DeliveryItem` transmiten actualizaciones vía Turbo Streams (`broadcast_delivery_updates`, `broadcast_item_row_update`) a streams compartidos por `delivery_id` — todo cliente suscrito a la página de detalle de una entrega recibe estos updates, independientemente de su rol.

## Puntos de mejora encontrados

1. **Bug de autorización — `Delivery#broadcast_delivery_updates`** (delivery.rb:637-654). Renderiza el partial `detail_header` con `can_edit`, `can_approve`, `can_reassign_seller`, `can_new_service_case`, `can_reopen`, `is_admin` **hardcodeados a `true`**, mientras que el render normal (`_detail_data.html.erb:7`) los saca de `policy(delivery).edit?` (Pundit). Resultado: cualquier usuario con la página de detalle abierta recibe, vía Turbo Stream, el panel de acciones de administrador (editar, aprobar, reabrir, etc.) sin importar su rol real. Hay que pasar la policy real por usuario suscrito, o al menos no otorgar permisos admin por defecto en el broadcast.

2. **Scope muerto y roto — `Order.active`** (order.rb:69). Filtra por `status: [:pending, ...]`, pero el enum de `Order` no tiene el valor `pending` (solo `in_production, ready_for_delivery, delivered, rescheduled, cancelled`). Llamarlo lanza `ArgumentError`. No tiene usos en el código (`grep` no encontró callers) — o se elimina o se corrige a `in_production`.

3. **Validación fantasma — `DeliveryItem#order_item_must_be_ready_to_confirm`** (delivery_item.rb:166-170). Está registrada como `validate ..., if: status_changed?(from: "pending", to: "confirmed")` pero el cuerpo está comentado — no valida nada. O se restaura la regla o se borra el `validate` y el método.

4. **Callback duplicado — `OrderItem`** (order_item.rb:38-56). `after_save :update_status_based_on_deliveries` y `after_update :update_order_status` corren ambos en cada update, y `update_status_based_on_deliveries` ya llama `update_order_status` internamente al final → `order.check_and_update_status!` se ejecuta dos veces por cada update de un `order_item`. No rompe nada pero duplica queries/transacciones sin necesidad.

5. **SQL triplicado — `Order` notes_status** (order.rb:73-109 y 184-222). El mismo `EXISTS (...)` (con/sin `closed`) está escrito tres veces como scopes y una cuarta vez dentro del `ransacker`. Un solo método privado que arme el SQL parametrizado por `with/open/closed` evitaría la duplicación y el riesgo de que diverjan si cambia el criterio.

## Estado de los fixes

Los 5 puntos ya están corregidos y verificados (suite completa: 251 tests, 0 fallos):

1. `broadcast_delivery_updates` ahora renderiza con todos los flags de permiso en `false` (fail-closed) en vez de `true` — el broadcast es un stream compartido entre todos los viewers y no puede calcular la policy real por usuario, así que ya no otorga acciones de admin a nadie por defecto.
2. `Order.active` corregido (quitado `:pending`, que no existe en el enum).
3. Validación fantasma `order_item_must_be_ready_to_confirm` eliminada de `DeliveryItem`.
4. Callback duplicado eliminado en `OrderItem` (`update_status_based_on_deliveries` ya llamaba `update_order_status` internamente).
5. SQL de `notes_status` unificado en `Order.notes_status_exists_sql`, usado por los 3 scopes y el ransacker.
