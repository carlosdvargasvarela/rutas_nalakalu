# Módulo: Jobs / Notificaciones

`app/jobs/` (9 jobs, mezcla de `ApplicationJob`/ActiveJob y `include Sidekiq::Job` directo), `app/services/notification_service.rb` (punto de entrada único de notificaciones in-app + email) y `app/mailers/` (6 mailers).

## Cómo funciona

- **`NotificationService.create_for_users`** es el único método que escribe en la tabla `notifications` (bulk insert) y dispara `NotificationMailer.safe_notify`. Todo `notify_*` de alto nivel arma destinatarios/mensaje y delega acá.
- **Admins reciben todo**: `create_for_users` agrega `User.where(role: :admin)` a la lista de destinatarios de cada notificación, sin excepción — comportamiento intencional (admins ven todo el flujo), no un bug.
- **Patrón "sin correo para mandados internos"**: varios métodos (`notify_current_week_delivery_created`, `notify_current_week_delivery_rescheduled`, `notify_bulk_items_rescheduled`, `notify_item_cancelled`) excluyen explícitamente `delivery.internal_delivery?` del correo externo (a `RESCHEDULE_NOTIFICATION_EMAILS`/`PLAN_EMAIL`) — un mandado interno no es una entrega real al cliente, así que no debe notificar a logística/plan externos.
- **Jobs de reporte** (`WeeklyAdminReportsJob`, `CurrentWeekUnconfirmedDeliveriesJob`, `SellerAddressErrors*Job`) son finos: delegan todo a servicios `AdminReports::*`/`SellerReports::*`.
- **Jobs Sidekiq directos** (`DeliveryImportPrepareJob`, `DeliveryImportProcessJob`, `ProcessQuickbooksXmlJob`, `SellerDeliverySummaryJob`) usan `include Sidekiq::Job` en vez de heredar `ApplicationJob` — inconsistente con el resto pero no es un bug (probablemente para opciones Sidekiq-específicas como `sidekiq_options retry:`).

## Puntos de mejora encontrados y corregidos

1. **`NotificationService.notify_delivery_rescheduled` no respetaba el patrón "sin correo externo para mandados internos"**. A diferencia de sus 3 métodos hermanos (`notify_current_week_delivery_rescheduled`, `notify_bulk_items_rescheduled`, `notify_item_cancelled`), este enviaba el correo detallado a `RESCHEDULE_NOTIFICATION_EMAILS` sin chequear `delivery.internal_delivery?`. Es el método que dispara `Deliveries::Rescheduler` y `DeliveryItems::Rescheduler` en **todo** reagendamiento — incluyendo mandados internos, que sí pasan por esos reschedulers. Corregido con el mismo guard que el resto (`return if delivery.internal_delivery?` antes de armar/enviar el correo externo).

2. **`DeliveryImportProcessJob`**: si `DeliveryImport.find(import_id)` fallaba (import inexistente), el `rescue` a nivel de método intentaba `import.update!(status: :failed, ...)` sobre un `import` que seguía siendo `nil` → `NoMethodError` enmascarando el error real (`RecordNotFound`). Corregido a `import&.update!(...)`.

## Tests agregados

`test/services/notification_service_test.rb` (2 tests) — verifica específicamente que `notify_delivery_rescheduled` NO llama `NotificationMailer.safe_notify_external` para `internal_delivery`, y SÍ lo hace para una entrega normal (para que el fix no quede sin cobertura y no pueda revertirse en silencio). No había ningún test previo para `NotificationService` — gap de cobertura conocido para el resto de sus ~15 métodos públicos.

**Suite completa: 262 tests, 0 fallos** (260 previos + 2 nuevos).
