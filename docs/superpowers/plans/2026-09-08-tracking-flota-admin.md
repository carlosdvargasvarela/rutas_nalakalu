# Dashboard de Tracking de Flota (Admin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir `/tracking`, una pantalla que muestra en un solo mapa la posición en vivo de todos los planes de entrega activos (todos los camiones a la vez), con alertas visuales de GPS perdido/detenido y la opción de ver el recorrido histórico de cada camión.

**Architecture:** Un controller nuevo (`TrackingsController`) sirve la carga inicial (planes activos + su última posición) y un endpoint de histórico bajo demanda (`delivery_plan_locations`). El tiempo real se logra reutilizando el canal ActionCable `DeliveryPlanChannel` que ya existe — el Stimulus controller nuevo abre una suscripción por plan activo, igual que ya hace `AdminDriverMapController` para un solo plan. Sin canal nuevo, sin migración, sin cambios al backend de broadcast existente.

**Tech Stack:** Rails 8, Pundit, ActionCable (canal existente), Stimulus + importmap-rails, Google Maps JS API, Minitest (`ActionDispatch::IntegrationTest` + `Devise::Test::IntegrationHelpers`).

**Spec:** `docs/superpowers/specs/2026-09-08-tracking-flota-admin-design.md`

## Global Constraints

- Visible para cualquier usuario autenticado salvo rol `driver` (spec §3, `TrackingPolicy`).
- Sin filtro por vendedor/cliente: cualquier rol con acceso ve la flota completa (spec §7).
- Alertas solo visuales, calculadas en cliente, sin persistencia ni notificación push/email (spec §3, §7).
- Reutilizar `DeliveryPlanChannel`/`subscribeToDeliveryPlan` existentes — no crear canal ActionCable nuevo (spec §2).
- Reutilizar el filtro de coordenadas inválidas (`lat/lng` 0 o nil se excluyen) que ya usan `admin_driver_map_controller.js` y `delivery_plan_map_controller.js` (spec §5).
- Sin tests automatizados de JS/Stimulus — verificación manual en navegador, como el resto de los map controllers del proyecto (spec §6).

---

### Task 1: `TrackingPolicy`

**Files:**
- Create: `app/policies/tracking_policy.rb`
- Test: `test/policies/tracking_policy_test.rb`

**Interfaces:**
- Consumes: nada (policy nueva, sin dependencias de tasks anteriores).
- Produces: `TrackingPolicy#index?` — usado por `TrackingsController` (Task 2) vía `authorize :tracking, :index?`.

- [ ] **Step 1: Escribir el test que falla**

```ruby
# test/policies/tracking_policy_test.rb
require "test_helper"

class TrackingPolicyTest < ActiveSupport::TestCase
  def test_index_true_for_non_driver_roles
    %w[admin manager production_manager seller logistics proveeduria].each do |role|
      user = users(:one)
      user.role = role
      assert TrackingPolicy.new(user, nil).index?, "#{role} debería poder ver /tracking"
    end
  end

  def test_index_false_for_driver
    user = users(:one)
    user.role = "driver"
    refute TrackingPolicy.new(user, nil).index?
  end
end
```

- [ ] **Step 2: Correr el test y confirmar que falla**

Run: `bin/rails test test/policies/tracking_policy_test.rb`
Expected: FAIL — `NameError: uninitialized constant TrackingPolicy`

- [ ] **Step 3: Implementar la policy**

```ruby
# app/policies/tracking_policy.rb
class TrackingPolicy < ApplicationPolicy
  def index?
    !user.driver?
  end
end
```

- [ ] **Step 4: Correr el test y confirmar que pasa**

Run: `bin/rails test test/policies/tracking_policy_test.rb`
Expected: PASS (2 runs, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/policies/tracking_policy.rb test/policies/tracking_policy_test.rb
git commit -m "feat: add TrackingPolicy for fleet tracking dashboard"
```

---

### Task 2: Ruta + `TrackingsController#index`

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/trackings_controller.rb`
- Test: `test/controllers/trackings_controller_test.rb`

**Interfaces:**
- Consumes: `TrackingPolicy` (Task 1).
- Produces: `GET /tracking` → `@plans` (Array de Hash serializados, ver Step 3) disponible para la vista (Task 4) como `@plans.to_json`. Ruta con nombre `tracking_path`.

- [ ] **Step 1: Escribir el test que falla**

```ruby
# test/controllers/trackings_controller_test.rb
require "test_helper"

class TrackingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "seller can see the fleet tracking dashboard" do
    seller = users(:one)
    seller.update!(role: :seller, force_password_change: false)
    sign_in seller

    get tracking_url
    assert_response :success
  end

  test "driver is redirected away from the fleet tracking dashboard" do
    driver = users(:one)
    driver.update!(role: :driver, force_password_change: false)
    sign_in driver

    get tracking_url
    assert_redirected_to root_url
  end

  test "index only includes active plans" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    active_plan = delivery_plans(:plan_for_driver)
    active_plan.update_columns(status: DeliveryPlan.statuses[:routes_created])
    draft_plan = delivery_plans(:one)
    draft_plan.update_columns(status: DeliveryPlan.statuses[:draft])

    get tracking_url
    assert_response :success
    assert_match active_plan.id.to_s, response.body
    refute_match(/"id":#{draft_plan.id}[,}]/, response.body)
  end
end
```

- [ ] **Step 2: Correr el test y confirmar que falla**

Run: `bin/rails test test/controllers/trackings_controller_test.rb`
Expected: FAIL — `ActionController::RoutingError` / `uninitialized constant TrackingsController`

- [ ] **Step 3: Agregar la ruta**

En `config/routes.rb`, agregar junto a la sección de `delivery_plans` (después del bloque que cierra en la línea 192, ver spec §3):

```ruby
  get "/tracking", to: "trackings#index", as: :tracking
```

- [ ] **Step 4: Implementar el controller**

```ruby
# app/controllers/trackings_controller.rb
class TrackingsController < ApplicationController
  def index
    authorize :tracking, :index?

    @plans = DeliveryPlan.active
      .includes(:driver, :last_recorded_by, delivery_plan_assignments: {delivery: [:delivery_address, order: :client]})
      .map { |plan| serialize_plan(plan) }
  end

  private

  def serialize_plan(plan)
    visible_assignments = plan.delivery_plan_assignments.reject { |a| a.delivery.hidden_from_route_map? }

    {
      id: plan.id,
      driver_name: plan.driver&.name || "Sin asignar",
      truck: plan.truck || "Sin asignar",
      current_lat: plan.current_lat&.to_f,
      current_lng: plan.current_lng&.to_f,
      last_seen_at: plan.last_seen_at,
      recorded_by_name: plan.last_recorded_by&.name,
      total_stops: visible_assignments.size,
      completed_stops: visible_assignments.count { |a| a.status == "completed" }
    }
  end
end
```

- [ ] **Step 5: Crear la vista mínima para que el test pase**

```erb
<%# app/views/trackings/index.html.erb %>
<div data-controller="fleet-tracking-map" data-fleet-tracking-map-plans-value="<%= @plans.to_json %>"></div>
```

(Esta vista se reemplaza por la definitiva en Task 4 — este paso solo destraba el test de Task 2.)

- [ ] **Step 6: Correr el test y confirmar que pasa**

Run: `bin/rails test test/controllers/trackings_controller_test.rb`
Expected: PASS (3 runs, 0 failures)

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/trackings_controller.rb app/views/trackings/index.html.erb test/controllers/trackings_controller_test.rb
git commit -m "feat: add TrackingsController#index for fleet tracking dashboard"
```

---

### Task 3: `TrackingsController#route` (histórico de recorrido)

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/trackings_controller.rb`
- Modify: `test/controllers/trackings_controller_test.rb`

**Interfaces:**
- Consumes: `TrackingPolicy` (Task 1), `DeliveryPlanLocation` (modelo existente, `app/models/delivery_plan_location.rb`).
- Produces: `GET /tracking/:delivery_plan_id/route` → JSON `[{lat:, lng:, captured_at:}, ...]` ordenado por `captured_at` ascendente. Ruta con nombre `tracking_route_path(delivery_plan_id:)`. Consumido por el Stimulus controller en Task 5.

- [ ] **Step 1: Escribir el test que falla**

```ruby
# agregar a test/controllers/trackings_controller_test.rb

  test "route returns ordered GPS pings for a plan" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    plan = delivery_plans(:plan_for_driver)
    plan.delivery_plan_locations.create!(latitude: 9.91, longitude: -84.01, captured_at: 1.hour.ago, source: "batch")
    plan.delivery_plan_locations.create!(latitude: 9.9, longitude: -84.0, captured_at: 2.hours.ago, source: "batch")

    get tracking_route_url(plan)
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body.size
    # Insertados en orden inverso a propósito: confirma que la respuesta
    # viene ordenada por captured_at ascendente, no por id de inserción.
    assert_equal [9.9, 9.91], body.map { |p| p["lat"] }
  end

  test "route is forbidden for drivers" do
    driver = users(:one)
    driver.update!(role: :driver, force_password_change: false)
    sign_in driver

    plan = delivery_plans(:plan_for_driver)
    get tracking_route_url(plan)
    assert_redirected_to root_url
  end
```

- [ ] **Step 2: Correr el test y confirmar que falla**

Run: `bin/rails test test/controllers/trackings_controller_test.rb`
Expected: FAIL — `ActionController::RoutingError` en `tracking_route_url`

- [ ] **Step 3: Agregar la ruta**

```ruby
  get "/tracking/:delivery_plan_id/route", to: "trackings#route", as: :tracking_route
```

- [ ] **Step 4: Implementar la acción**

```ruby
  def route
    authorize :tracking, :index?
    plan = DeliveryPlan.find(params[:delivery_plan_id])

    points = plan.delivery_plan_locations.ordered.map do |loc|
      {lat: loc.latitude.to_f, lng: loc.longitude.to_f, captured_at: loc.captured_at}
    end

    render json: points
  end
```

- [ ] **Step 5: Correr los tests y confirmar que pasan**

Run: `bin/rails test test/controllers/trackings_controller_test.rb`
Expected: PASS (5 runs, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/trackings_controller.rb test/controllers/trackings_controller_test.rb
git commit -m "feat: add TrackingsController#route for GPS history polyline"
```

---

### Task 4: Vista definitiva + link en el nav

**Files:**
- Modify: `app/views/trackings/index.html.erb`
- Modify: `app/views/layouts/_navbar_links.html.erb`

**Interfaces:**
- Consumes: `@plans` (Task 2), `tracking_path`/`tracking_route_path` (Tasks 2-3), `policy(:tracking).index?` (Pundit, vía `TrackingPolicy` de Task 1).
- Produces: markup con los `data-*` attributes que el Stimulus controller de Task 5 necesita: `data-controller="fleet-tracking-map"`, `data-fleet-tracking-map-plans-value`, target `map` y target `list` (panel lateral), `data-fleet-tracking-map-api-key-value`.

- [ ] **Step 1: Escribir la vista**

```erb
<%# app/views/trackings/index.html.erb %>
<div class="container-fluid py-4">
  <h1 class="h4 mb-4"><i class="bi bi-broadcast text-success me-2"></i>Seguimiento de flota</h1>

  <div class="row g-3"
       data-controller="fleet-tracking-map"
       data-fleet-tracking-map-api-key-value="<%= ENV['GOOGLE_MAPS_API_KEY'] %>"
       data-fleet-tracking-map-plans-value="<%= @plans.to_json %>">
    <div class="col-lg-8">
      <div class="card shadow-sm">
        <div style="height:650px" data-fleet-tracking-map-target="map"></div>
      </div>
    </div>
    <div class="col-lg-4">
      <div class="card shadow-sm">
        <div class="card-header bg-white fw-semibold">Camiones activos (<%= @plans.size %>)</div>
        <ul class="list-group list-group-flush" data-fleet-tracking-map-target="list">
          <% if @plans.empty? %>
            <li class="list-group-item text-muted small">No hay planes activos en este momento.</li>
          <% end %>
        </ul>
      </div>
    </div>
  </div>
</div>
```

(La lista de camiones se puebla y actualiza en JS a partir de `plansValue` — el servidor solo pasa el estado inicial y el mensaje de "vacío"; Task 5 la llena.)

- [ ] **Step 2: Agregar el link al nav**

En `app/views/layouts/_navbar_links.html.erb`, después del `</li>` de "Planes de Entrega" (línea 22) y antes del comentario `OPERACIONES`:

```erb
  <% if policy(:tracking).index? %>
    <li class="nav-item">
      <%= link_to tracking_path, class: "nav-link" do %>
        <i class="bi bi-broadcast me-1 text-success"></i> Seguimiento
      <% end %>
    </li>
  <% end %>
```

- [ ] **Step 3: Verificar que los controller tests de Tasks 2-3 siguen pasando**

Run: `bin/rails test test/controllers/trackings_controller_test.rb`
Expected: PASS (5 runs, 0 failures) — la vista nueva no debe romper nada, ya que sigue exponiendo los mismos `data-*` que la vista mínima del Task 2.

- [ ] **Step 4: Commit**

```bash
git add app/views/trackings/index.html.erb app/views/layouts/_navbar_links.html.erb
git commit -m "feat: add fleet tracking dashboard view and nav link"
```

---

### Task 5: `fleet_tracking_map_controller.js` — mapa en vivo, panel lateral y alertas

**Files:**
- Create: `app/javascript/controllers/fleet_tracking_map_controller.js`

**Interfaces:**
- Consumes: `subscribeToDeliveryPlan(deliveryPlanId, callback)` de `channels/delivery_plan_channel.js` (ya existe, sin cambios — devuelve un objeto con `.unsubscribe()`). Cada plan recibido por callback trae `{type: "position_update", current_lat, current_lng, last_seen_at, recorded_by_name}` (payload ya emitido hoy por `Api::V1::Driver::DeliveryPlansController#update_position_batch`). `plansValue` (Array) con la forma serializada en Task 2 (`id, driver_name, truck, current_lat, current_lng, last_seen_at, recorded_by_name, total_stops, completed_stops`).
- Produces: nada consumido por otras tasks — es el punto final de la cadena de datos.

- [ ] **Step 1: Esqueleto del controller — carga inicial de markers**

```js
// app/javascript/controllers/fleet_tracking_map_controller.js
import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "channels/delivery_plan_channel";

const STALE_MINUTES = 5;
const STOPPED_MINUTES = 10;

export default class extends Controller {
  static targets = ["map", "list"];
  static values = { apiKey: String, plans: Array };

  connect() {
    this.trucks = new Map(); // planId -> { data, marker, subscription, row, routePolyline }
    this.subscriptions = [];
    this.initMap();
  }

  disconnect() {
    this.subscriptions.forEach((s) => s.unsubscribe());
    if (this.alertInterval) clearInterval(this.alertInterval);
  }

  async initMap() {
    await this.waitForGoogleMaps();

    this.map = new google.maps.Map(this.mapTarget, {
      center: { lat: 9.9281, lng: -84.0907 },
      zoom: 10,
      mapTypeControl: false,
      streetViewControl: false,
    });

    const bounds = new google.maps.LatLngBounds();
    let hasValidPosition = false;

    this.plansValue.forEach((plan) => {
      this.addTruck(plan);
      if (this._validCoord(plan.current_lat) && this._validCoord(plan.current_lng)) {
        bounds.extend({ lat: plan.current_lat, lng: plan.current_lng });
        hasValidPosition = true;
      }
    });

    if (hasValidPosition) this.map.fitBounds(bounds);

    this.alertInterval = setInterval(() => this.refreshAlerts(), 30000);
    this.refreshAlerts();
  }

  async waitForGoogleMaps() {
    if (window.google?.maps) return;
    if (!document.querySelector("#google-maps-script")) {
      const script = document.createElement("script");
      script.id = "google-maps-script";
      script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}`;
      script.async = true;
      document.head.appendChild(script);
    }
    return new Promise((resolve) => {
      const check = () => (window.google?.maps ? resolve() : setTimeout(check, 200));
      check();
    });
  }

  _validCoord(v) {
    return v !== 0 && v !== null && Number.isFinite(v);
  }
}
```

- [ ] **Step 2: Agregar `addTruck` (marker + fila del panel lateral)**

```js
// agregar dentro de la clase

  addTruck(plan) {
    const row = this.buildRow(plan);
    this.listTarget.appendChild(row);

    let marker = null;
    if (this._validCoord(plan.current_lat) && this._validCoord(plan.current_lng)) {
      marker = new google.maps.Marker({
        position: { lat: plan.current_lat, lng: plan.current_lng },
        map: this.map,
        icon: {
          path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
          scale: 6,
          fillColor: "#0d6efd",
          fillOpacity: 1,
          strokeColor: "#ffffff",
          strokeWeight: 2,
        },
        title: plan.driver_name,
      });
      marker.addListener("click", () => this.map.panTo(marker.getPosition()));
    }

    const subscription = subscribeToDeliveryPlan(plan.id, (data) => {
      if (data.type !== "position_update") return;
      this.updateTruckPosition(plan.id, data);
    });
    this.subscriptions.push(subscription);

    this.trucks.set(plan.id, {
      data: { ...plan },
      marker,
      row,
      routePolyline: null,
      lastMovedAt: plan.last_seen_at ? new Date(plan.last_seen_at).getTime() : null,
    });
  }

  buildRow(plan) {
    const row = document.createElement("li");
    row.className = "list-group-item";
    row.dataset.planId = plan.id;
    row.innerHTML = `
      <div class="d-flex justify-content-between align-items-start">
        <div>
          <strong>${this._escapeHtml(plan.driver_name)}</strong>
          <div class="small text-muted">${this._escapeHtml(plan.truck)} — ${plan.completed_stops}/${plan.total_stops} paradas</div>
          <div class="small text-muted" data-role="last-seen"></div>
        </div>
        <span class="badge" data-role="alert-badge"></span>
      </div>
      <button type="button" class="btn btn-sm btn-outline-secondary mt-2" data-role="route-toggle">
        Ver recorrido
      </button>
    `;
    row.querySelector('[data-role="route-toggle"]').addEventListener("click", () => this.toggleRoute(plan.id));
    return row;
  }

  _escapeHtml(str) {
    return String(str ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }
```

- [ ] **Step 3: Agregar `updateTruckPosition` y `refreshAlerts`**

```js
// agregar dentro de la clase

  updateTruckPosition(planId, { current_lat, current_lng, last_seen_at, recorded_by_name }) {
    const truck = this.trucks.get(planId);
    if (!truck) return;

    const lat = parseFloat(current_lat);
    const lng = parseFloat(current_lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

    // "Detenido" mide si la posición cambió, no solo si llegó un mensaje —
    // el driver puede seguir enviando batches idénticos mientras espera en una parada.
    const moved = truck.data.current_lat !== lat || truck.data.current_lng !== lng;
    if (moved || !truck.lastMovedAt) truck.lastMovedAt = Date.now();

    truck.data.current_lat = lat;
    truck.data.current_lng = lng;
    truck.data.last_seen_at = last_seen_at;
    truck.data.recorded_by_name = recorded_by_name;

    const position = { lat, lng };
    if (truck.marker) {
      truck.marker.setPosition(position);
    } else {
      truck.marker = new google.maps.Marker({
        position,
        map: this.map,
        icon: {
          path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
          scale: 6,
          fillColor: "#0d6efd",
          fillOpacity: 1,
          strokeColor: "#ffffff",
          strokeWeight: 2,
        },
        title: truck.data.driver_name,
      });
    }

    this.refreshAlerts();
  }

  refreshAlerts() {
    const now = Date.now();

    this.trucks.forEach((truck) => {
      const lastSeenEl = truck.row.querySelector('[data-role="last-seen"]');
      const badgeEl = truck.row.querySelector('[data-role="alert-badge"]');

      if (!truck.data.last_seen_at) {
        lastSeenEl.textContent = "Sin datos GPS";
        badgeEl.textContent = "";
        return;
      }

      const minutesSinceSeen = (now - new Date(truck.data.last_seen_at).getTime()) / 60000;
      lastSeenEl.textContent = `Última actualización: hace ${Math.max(0, Math.round(minutesSinceSeen))} min`;

      const minutesSinceMoved = truck.lastMovedAt ? (now - truck.lastMovedAt) / 60000 : minutesSinceSeen;

      if (minutesSinceSeen > STALE_MINUTES) {
        badgeEl.textContent = "GPS perdido";
        badgeEl.className = "badge bg-danger";
      } else if (minutesSinceMoved > STOPPED_MINUTES) {
        badgeEl.textContent = "Detenido";
        badgeEl.className = "badge bg-warning text-dark";
      } else {
        badgeEl.textContent = "";
        badgeEl.className = "badge";
      }
    });
  }
```

`STALE_MINUTES` (5) sigue siendo menor que `STOPPED_MINUTES` (10) a propósito: si ya pasaron 5 min sin ningún mensaje del todo, es "GPS perdido" (peor señal, gana la alerta). Si los mensajes siguen llegando pero la posición no cambia por 10 min, es "Detenido". `truck.lastMovedAt` se inicializa en `addTruck` (Step 2) — agregarlo ahí como `lastMovedAt: plan.last_seen_at ? new Date(plan.last_seen_at).getTime() : null` al construir el objeto que se guarda en `this.trucks`.

- [ ] **Step 4: Agregar `toggleRoute` (histórico bajo demanda)**

```js
// agregar dentro de la clase

  async toggleRoute(planId) {
    const truck = this.trucks.get(planId);
    if (!truck) return;

    if (truck.routePolyline) {
      truck.routePolyline.setMap(null);
      truck.routePolyline = null;
      return;
    }

    const response = await fetch(`/tracking/${planId}/route`);
    if (!response.ok) return;
    const points = await response.json();
    if (!points.length) return;

    truck.routePolyline = new google.maps.Polyline({
      path: points.map((p) => ({ lat: p.lat, lng: p.lng })),
      geodesic: true,
      strokeColor: "#6f42c1",
      strokeOpacity: 0.8,
      strokeWeight: 3,
      map: this.map,
    });

    const bounds = new google.maps.LatLngBounds();
    points.forEach((p) => bounds.extend({ lat: p.lat, lng: p.lng }));
    this.map.fitBounds(bounds);
  }
```

- [ ] **Step 5: Verificación manual en navegador**

1. `bin/dev` (o el comando de arranque local del proyecto).
2. Con un usuario `seller` o `admin`, entrar a `/tracking`.
3. Confirmar: aparece un marker por cada plan `active` con posición válida; la lista lateral muestra conductor, camión y progreso.
4. Simular una actualización de posición (ej. `DeliveryPlanChannel.broadcast_to(plan, {type: "position_update", current_lat: ..., current_lng: ..., last_seen_at: Time.current, recorded_by_name: "Test"})` desde `bin/rails console`) y confirmar que el marker se mueve sin recargar la página.
5. Click en "Ver recorrido" de un plan con datos en `delivery_plan_locations` (crear alguno vía consola si hace falta) y confirmar que dibuja la polyline; click de nuevo la oculta.
6. Entrar como usuario `driver` y confirmar que `/tracking` redirige (no debería llegar al link del nav tampoco).

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/fleet_tracking_map_controller.js
git commit -m "feat: add live fleet tracking map with alerts and route history"
```
