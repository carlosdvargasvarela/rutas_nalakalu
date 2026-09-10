# Módulo: DeliveriesController

Controlador central de la app (67 edges en el grafo). CRUD de {Delivery} + ~35 acciones operativas: aprobar, marcar entregado, bodegaje, dividir, reagendar, casos de servicio/reparación (nuevos y sobre entrega existente), retiro en sala, movimientos de showroom, mandados internos.

## Estructura

- **`before_action :set_delivery`**: precarga `@delivery` (con includes) para casi todas las acciones que operan sobre una entrega existente.
- **Patrón de respuesta dual**: casi toda acción de escritura responde `format.html` (redirect con notice/alert) y `format.turbo_stream` (actualiza el panel de detalle + tarjeta del índice en vivo). `render_delivery_update_stream` (privado) centraliza ese segundo caso para las acciones más simples; las que tocan más partials (approve, reopen, sala pickup, workspace de servicio/reparación) arman su propio array de `turbo_stream.replace`.
- **Creators**: la lógica de creación compleja vive en `app/services/deliveries/*Creator` (Creator, InternalCreator, ServiceCaseCreator, RepairServiceCreator, SalaPickupCreator, ShowroomMovementCreator, etc.) — el controller solo arma params y delega.
- **`by_week` / `service_cases`**: variantes de `index` que reusan la misma vista con un scope distinto.

## Puntos de mejora encontrados y corregidos

1. **🔴 Bug — `by_week` y `service_cases` estaban rotas (500 en cada visita)**. Ninguna de las dos seteaba `@q` (objeto `Ransack::Search`), que la vista compartida `deliveries/index.html.erb` requiere (`search_form_for @q`) — ni llamaban `authorize`, lo que además habría hecho fallar el `after_action :verify_authorized` global si hubieran llegado hasta ahí. Confirmado con un test de integración real (`ActionView::Template::Error: No Ransack::Search object was provided`) antes del fix. Corregido: ambas arman `@q`, `@sellers` y llaman `authorize Delivery, :index?` igual que `index`. Sin tests previos sobre estas rutas — por eso nadie lo notó; se agregaron 2 tests de regresión.

2. **SQL no portable — `Delivery.for_week`** usaba `EXTRACT(week FROM delivery_date)` (sintaxis Postgres-only). Funciona en producción (Postgres) pero no en test/dev (SQLite), lo que hacía imposible testear `by_week` sin un fix aparte. Reescrito como rango de fechas (`delivery_date: date.beginning_of_week..date.end_of_week`), equivalente pero portable y más eficiente (usa índice sobre `delivery_date` en vez de una función sobre cada fila).

3. **`authorize Delivery` duplicado en `index`** (una vez al inicio, otra antes del `respond_to`). Redundante, no rompía nada — se dejó solo la primera llamada.

4. **Query redundante en `create_repair_service_for_existing`**: la acción está en la lista de `before_action :set_delivery` (que ya carga `@delivery` con includes), pero además hacía `Delivery.find(params[:id])` de nuevo con una segunda query sin includes. Corregido para reusar `@delivery`.

Suite completa verificada después de cada cambio: **253 tests, 0 fallos** (251 previos + 2 nuevos de regresión para by_week/service_cases).

## Documentación agregada

Docstring de clase + comentarios cortos en las acciones cuyo comportamiento no es obvio por el nombre (`split`, `propagate_to_associated`, `by_week`, `service_cases`, `create_service_case_from_workspace`, `create_repair_service_from_workspace`). No se agregó YARD método-por-método como en los modelos — en un controller Rails con nombres de acción estándar (`index`, `show`, `create`, etc.) la mayoría ya es autoexplicativa; documentar cada una sería ruido.
