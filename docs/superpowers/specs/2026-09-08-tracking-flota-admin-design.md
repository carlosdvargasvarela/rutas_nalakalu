# Dashboard de tracking de flota (admin/vendedores/logística)

**Fecha:** 2026-09-08
**Alcance:** Nueva pantalla `/tracking` que muestra en un solo mapa la posición en vivo de todos los planes de entrega activos, visible para todos los roles autenticados salvo `driver`. Alertas visuales básicas de GPS perdido/camión detenido. No incluye histórico de recorrido ni notificaciones push/email (quedan para una segunda entrega).

---

## 1. Contexto y problema

El tracking en vivo por plan individual ya existe y funciona (`delivery_plans#show`, tab "Seguimiento en vivo", `AdminDriverMapController` + `DeliveryPlanChannel` vía ActionCable). Lo que falta es una vista agregada: hoy, para saber dónde está cada camión activo, hay que entrar plan por plan.

Este módulo llevaba casi un año sin terminarse. Se rediseña desde cero, reutilizando toda la infraestructura de tracking en vivo que ya existe (broadcast de posición, canal ActionCable, cálculo de `last_seen_at`/`last_recorded_by`) en vez de crear una capa nueva de tiempo real.

**Gap actual de visibilidad:** `DeliveryPlanPolicy::Scope` limita a roles no-admin/logística/producción a `where(driver_id: user.id)` — un vendedor no ve ningún plan hoy. El dashboard nuevo necesita su propia policy para no alterar ese comportamiento en la gestión de planes (donde sí tiene sentido restringir).

---

## 2. Decisión de arquitectura

**Reutilizar `DeliveryPlanChannel` existente, una suscripción por plan activo, en vez de crear un canal agregado (`FleetTrackingChannel`).**

Se descartó un canal agregado porque requeriría duplicar el broadcast en `update_position_batch` (backend) para un beneficio (una sola suscripción en vez de N) que no se justifica con el volumen real de camiones activos simultáneos. N suscripciones ligeras a un canal que ya emite exactamente lo que necesitamos es la opción más simple y de menor riesgo (cero cambios al backend de broadcast, que ya está probado en producción).

Se descartó polling porque el resto del sistema ya usa ActionCable para esto; introducir un segundo mecanismo de actualización sería inconsistente sin aportar nada.

---

## 3. Componentes

### Ruta y controller
- `GET /tracking` → `TrackingsController#index`
- Carga `DeliveryPlan.active` con `includes(:driver, delivery_plan_assignments: {delivery: [:delivery_address, order: :client]})` — mismo patrón de precarga que `delivery_plans_controller`.
- Serializa a JSON embebido en la vista (igual que `_driver.html.erb` hace hoy con `assignments`): id, conductor, camión, `current_lat/lng`, `last_seen_at`, `last_recorded_by`, cantidad de paradas totales/completadas.

### Policy nueva: `TrackingPolicy`
```ruby
class TrackingPolicy < ApplicationPolicy
  def index?
    !user.driver?
  end
end
```
No toca `DeliveryPlanPolicy` ni su `Scope`. El controller usa `DeliveryPlan.active` directo (sin `policy_scope`), porque el requisito acordado es "toda la flota sin filtro" para cualquier rol con acceso — no hay escopeo por usuario dentro del dashboard.

### Vista + Stimulus: `fleet_tracking_map_controller.js`
- Un marker por plan activo con posición válida (mismo filtro de coordenadas 0/nil que ya usa `admin_driver_map_controller.js`).
- Al conectar, se suscribe a `DeliveryPlanChannel` (helper `subscribeToDeliveryPlan` ya existente en `channels/delivery_plan_channel.js`) por cada plan de la lista inicial — reutiliza el mismo mecanismo que el tracking por-plan.
- Panel lateral: lista de camiones activos con conductor, progreso (`completadas/total`), última actualización.
- Click en un camión → centra el mapa en su marker y resalta su fila (sin navegar fuera de la página; el link "ver plan completo" sigue yendo a `delivery_plans#show`).

### Alertas visuales (sin backend nuevo)
Calculadas en el cliente, recalculadas cada 30s con `setInterval` sobre los datos ya recibidos (no requiere query nueva):
- `last_seen_at` > 5 min → badge rojo "GPS perdido" en marker y fila.
- Plan `in_progress` con posición sin cambio > 10 min → badge naranja "Detenido".
Ambos son puramente visuales — ni se persisten ni disparan notificación.

### Navegación
Link nuevo en el nav principal, visible para todos los roles salvo `driver` (mismo criterio que `TrackingPolicy#index?`).

---

## 4. Flujo de datos

1. `TrackingsController#index` arma la lista inicial de planes activos + posición actual (carga fría, sin ActionCable).
2. La vista embebe esa lista como `data-fleet-tracking-map-plans-value` (JSON), igual patrón que `_driver.html.erb`.
3. `fleet_tracking_map_controller.js` pinta los markers iniciales y abre N suscripciones (una por `delivery_plan_id` de la lista).
4. Cada `position_update` recibido por `DeliveryPlanChannel` (mismo payload que ya usa el tracking por-plan: `current_lat`, `current_lng`, `last_seen_at`, `recorded_by_name`) actualiza el marker correspondiente y su fila en el panel lateral.
5. Si un nuevo plan pasa a `in_progress` mientras la página está abierta, no aparece hasta refrescar (fuera de alcance: no hay canal de "nuevo plan activo"; se acepta como limitación conocida de esta primera entrega).

---

## 5. Manejo de errores

- Plan sin `current_lat/current_lng` (aún no envió ninguna posición): se lista en el panel lateral sin marker en el mapa, con nota "Sin GPS aún" (mismo criterio que el resto de mapas del proyecto, que ya excluyen coordenadas 0/nil).
- Falla la suscripción a un canal individual (ej. plan finalizado entre la carga y la suscripción): se ignora ese plan silenciosamente, igual que hoy hace `admin_driver_map_controller.js` si el plan ya no está activo.
- Google Maps no carga: mismo patrón de `waitForGoogleMaps`/reintento que ya usan los otros controllers de mapa del proyecto.

---

## 6. Testing

- Request spec `TrackingsController#index`: 200 para cada rol salvo `driver` (403/redirect), payload incluye solo planes `active`.
- Policy spec `TrackingPolicy`.
- Sin test de JS/Stimulus (no hay precedente de esto en el proyecto para los otros map controllers — se verifica manualmente en navegador, igual que los mapas existentes).

---

## 7. Fuera de alcance (explícitamente diferido)

- Histórico de recorrido (trazo real del camino) — requiere tabla nueva de pings de posición; hoy `update_position_batch` solo persiste el último punto del batch.
- Notificaciones push/email por alertas — solo visual por ahora.
- Filtro de vendedor por sus propios clientes — se decidió flota completa sin filtro para todos los roles con acceso.
