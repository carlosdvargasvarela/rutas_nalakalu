# Production/Delivery Plans Revamp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rediseñar el módulo `production/delivery_plans` con tema oscuro vibrante, botones táctiles grandes para mobile, y bottom sheet de notas por producto.

**Architecture:** CSS custom properties scoped a `.production-dark`; vistas rediseñadas respetando los IDs de Turbo Stream existentes; nueva acción `add_note` en `Production::DeliveryItemsController`; bottom sheet gestionado por un nuevo `note_sheet_controller.js` que se comunica con `delivery_item_controller.js` via eventos DOM.

**Tech Stack:** Rails 7, Turbo Streams, Stimulus JS, Bootstrap Icons (`bi bi-*`), CSS custom properties, Minitest.

**Spec:** `docs/superpowers/specs/2026-05-22-production-delivery-plans-revamp-design.md`

---

## Mapa de archivos

| Acción | Archivo |
|---|---|
| Crear | `app/assets/stylesheets/production.css` |
| Crear | `app/javascript/controllers/note_sheet_controller.js` |
| Crear | `test/controllers/production/delivery_items_controller_test.rb` |
| Modificar | `config/routes.rb` |
| Modificar | `app/controllers/production/delivery_items_controller.rb` |
| Modificar | `app/policies/delivery_item_policy.rb` |
| Modificar | `app/views/production/delivery_plans/index.html.erb` |
| Modificar | `app/views/production/delivery_plans/loading.html.erb` |
| Modificar | `app/views/production/delivery_plans/_plan_header.html.erb` |
| Modificar | `app/views/production/delivery_plans/_load_summary.html.erb` |
| Modificar | `app/views/production/deliveries/_delivery_card.html.erb` |
| Modificar | `app/views/production/delivery_items/_delivery_item_row.html.erb` |
| Modificar | `app/javascript/controllers/delivery_item_controller.js` |

---

## Task 1: CSS Foundation

**Files:**
- Create: `app/assets/stylesheets/production.css`
- Check: `app/assets/stylesheets/application.css` (verificar si `require_tree .` ya incluye el directorio)

- [ ] **Step 1: Verificar si production.css se incluirá automáticamente**

```bash
grep -n "require_tree\|require production" app/assets/stylesheets/application.css
```

Si la salida contiene `require_tree .` → el archivo se incluirá solo al crearlo. Si no, agregar `*= require production` antes de `*= require_self`.

- [ ] **Step 2: Crear `app/assets/stylesheets/production.css`**

```css
/* ============================================================
   PRODUCTION MODULE — Dark Vibrant Theme
   Scope: .production-dark wrapper en todas las vistas production/
   ============================================================ */

/* ── Variables ── */
.production-dark {
  --pd-bg:            #0f0f1a;
  --pd-card:          #1a1a2e;
  --pd-card-inner:    #12122a;
  --pd-border:        #2d2d4e;
  --pd-accent:        #7c3aed;
  --pd-text:          #f1f5f9;
  --pd-muted:         #64748b;
  --pd-success-text:  #4ade80;
  --pd-success-bg:    #166534;
  --pd-success-item:  #051c0a;
  --pd-danger-text:   #f87171;
  --pd-danger-bg:     #7f1d1d;
  --pd-danger-item:   #1c0505;
  --pd-warning-text:  #fbbf24;
  --pd-warning-bg:    #78350f;
  --pd-note-text:     #fde68a;

  background: var(--pd-bg);
  min-height: 100vh;
  color: var(--pd-text);
}

/* ── Header gradient ── */
.pd-header {
  background: linear-gradient(160deg, #6d28d9 0%, #4338ca 60%, #1e1b4b 100%);
  padding: 14px 16px 16px;
}

/* ── Cards ── */
.pd-card {
  background: var(--pd-card);
  border: 1px solid var(--pd-border);
  border-radius: 16px;
  overflow: hidden;
}

.pd-card-top {
  height: 3px;
  width: 100%;
}

/* ── Stats cells ── */
.pd-stat-cell {
  background: var(--pd-card);
  border: 1px solid var(--pd-border);
  border-radius: 12px;
  text-align: center;
  padding: 10px 6px;
}

.pd-mini-stat {
  background: var(--pd-card-inner);
  border-radius: 8px;
  text-align: center;
  padding: 8px 4px;
}

/* ── Progress bar ── */
.pd-progress-wrap {
  height: 9px;
  background: rgba(255,255,255,0.1);
  border-radius: 5px;
  overflow: hidden;
}

.pd-progress-bar {
  height: 100%;
  border-radius: 5px;
  transition: width 0.3s ease;
}

/* ── Badges ── */
.pd-badge {
  font-size: 0.7rem;
  padding: 3px 10px;
  border-radius: 20px;
  font-weight: 700;
  display: inline-block;
}

.pd-badge--ok      { background: var(--pd-success-bg); color: var(--pd-success-text); }
.pd-badge--missing { background: var(--pd-danger-bg);  color: var(--pd-danger-text);  }
.pd-badge--partial { background: var(--pd-warning-bg); color: var(--pd-warning-text); }
.pd-badge--pending { background: var(--pd-card); color: var(--pd-muted); border: 1px solid var(--pd-border); }

/* ── Driver avatar ── */
.pd-avatar {
  border-radius: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 800;
  color: #fff;
  flex-shrink: 0;
  background: linear-gradient(135deg, #6d28d9, #4f46e5);
}

/* ── Filter chips ── */
.pd-filter-bar {
  background: var(--pd-card-inner);
  padding: 8px 12px;
  display: flex;
  gap: 6px;
  overflow-x: auto;
  border-bottom: 1px solid var(--pd-border);
  -webkit-overflow-scrolling: touch;
}
.pd-filter-bar::-webkit-scrollbar { display: none; }

.pd-chip {
  font-size: 0.75rem;
  padding: 5px 12px;
  border-radius: 20px;
  font-weight: 600;
  white-space: nowrap;
  flex-shrink: 0;
  cursor: pointer;
  text-decoration: none;
  border: 1px solid transparent;
  transition: background 0.15s;
}

.pd-chip--all     { background: var(--pd-accent); color: #fff; }
.pd-chip--unloaded{ background: var(--pd-card); color: var(--pd-muted); border-color: var(--pd-border); }
.pd-chip--partial { background: var(--pd-card); color: var(--pd-warning-text); border-color: #78350f44; }
.pd-chip--loaded  { background: var(--pd-card); color: var(--pd-success-text); border-color: #16653444; }
.pd-chip--missing { background: var(--pd-card); color: var(--pd-danger-text);  border-color: #7f1d1d44; }

/* ── Search input ── */
.pd-search-wrap {
  background: var(--pd-card-inner);
  padding: 8px 12px 10px;
}

.pd-search-input {
  width: 100%;
  background: var(--pd-card);
  border: 1px solid var(--pd-border);
  border-radius: 12px;
  color: var(--pd-text);
  font-size: 0.875rem;
  padding: 9px 12px 9px 36px;
  outline: none;
}

.pd-search-input::placeholder { color: var(--pd-muted); }
.pd-search-input:focus { border-color: var(--pd-accent); }

.pd-search-icon {
  position: absolute;
  left: 22px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--pd-muted);
  font-size: 0.875rem;
  pointer-events: none;
}

/* ── Delivery card collapsible header ── */
.pd-del-hdr {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 11px 14px;
  cursor: pointer;
  user-select: none;
}

.pd-stop-badge {
  width: 30px;
  height: 30px;
  border-radius: 9px;
  background: var(--pd-accent);
  color: #fff;
  font-size: 0.75rem;
  font-weight: 800;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.pd-stop-badge--done { background: var(--pd-success-bg); }
.pd-stop-badge--pending { background: var(--pd-border); color: var(--pd-muted); }

/* ── Item rows ── */
.pd-item-row {
  padding: 10px 14px;
  border-bottom: 1px solid var(--pd-card-inner);
  background: var(--pd-card);
}

.pd-item-row:last-child { border-bottom: none; }
.pd-item-row--loaded  { background: var(--pd-success-item); }
.pd-item-row--missing { background: var(--pd-danger-item); }

/* ── Action buttons — mínimo 44px para touch ── */
.pd-btn-ok {
  flex: 3;
  background: linear-gradient(135deg, #15803d, #16a34a);
  color: #dcfce7;
  border-radius: 11px;
  padding: 11px 0;
  text-align: center;
  font-size: 0.8rem;
  font-weight: 800;
  border: none;
  cursor: pointer;
  text-decoration: none;
  display: block;
}

.pd-btn-miss {
  flex: 3;
  background: var(--pd-danger-item);
  color: var(--pd-danger-text);
  border-radius: 11px;
  padding: 11px 0;
  text-align: center;
  font-size: 0.8rem;
  font-weight: 700;
  border: 1px solid var(--pd-danger-bg);
  cursor: pointer;
  text-decoration: none;
  display: block;
}

.pd-btn-undo {
  flex: 2;
  background: var(--pd-card);
  color: var(--pd-muted);
  border-radius: 11px;
  padding: 11px 0;
  text-align: center;
  font-size: 0.75rem;
  border: 1px solid var(--pd-border);
  cursor: pointer;
  text-decoration: none;
  display: block;
}

.pd-btn-note {
  width: 44px;
  background: var(--pd-card);
  color: var(--pd-muted);
  border-radius: 11px;
  padding: 11px 0;
  text-align: center;
  font-size: 1rem;
  border: 1px solid var(--pd-border);
  cursor: pointer;
  display: block;
  flex-shrink: 0;
}

.pd-btn-note--active { color: var(--pd-note-text); border-color: #f59e0b44; }
.pd-btn-note--loaded { color: var(--pd-success-text); border-color: #16653444; }

/* ── Card footer (mark all) ── */
.pd-card-footer {
  border-top: 1px solid var(--pd-card-inner);
  padding: 8px 14px;
  display: flex;
  gap: 8px;
  background: var(--pd-card-inner);
}

.pd-btn-all {
  flex: 1;
  background: var(--pd-success-bg);
  color: var(--pd-success-text);
  border-radius: 10px;
  padding: 8px;
  text-align: center;
  font-size: 0.75rem;
  font-weight: 700;
  border: none;
  cursor: pointer;
}

.pd-btn-reset {
  background: var(--pd-card);
  color: var(--pd-muted);
  border-radius: 10px;
  padding: 8px 12px;
  text-align: center;
  font-size: 0.8rem;
  border: 1px solid var(--pd-border);
  cursor: pointer;
}

/* ── Note preview ── */
.pd-note-preview {
  font-size: 0.72rem;
  color: var(--pd-note-text);
  font-style: italic;
  margin-top: 3px;
}

/* ── Bottom sheet ── */
.pd-sheet-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.65);
  z-index: 1040;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.2s ease;
}

.pd-sheet {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  z-index: 1041;
  background: #1e1e38;
  border-radius: 24px 24px 0 0;
  padding: 12px 20px 32px;
  box-shadow: 0 -8px 40px rgba(0,0,0,0.6);
  transform: translateY(100%);
  transition: transform 0.25s ease-out;
  max-width: 600px;
  margin: 0 auto;
}

.pd-sheet-open .pd-sheet-overlay {
  opacity: 1;
  pointer-events: auto;
}

.pd-sheet-open .pd-sheet {
  transform: translateY(0);
}

.pd-sheet-handle {
  width: 40px;
  height: 4px;
  background: var(--pd-border);
  border-radius: 2px;
  margin: 0 auto 14px;
}

.pd-sheet-product {
  font-size: 0.8rem;
  color: var(--pd-accent);
  background: #7c3aed1a;
  padding: 5px 10px;
  border-radius: 8px;
  display: inline-block;
  margin-bottom: 12px;
}

.pd-sheet-textarea {
  width: 100%;
  background: var(--pd-card-inner);
  border: 1px solid var(--pd-border);
  border-radius: 12px;
  color: var(--pd-note-text);
  font-size: 0.9rem;
  padding: 12px;
  resize: none;
  height: 90px;
  outline: none;
  font-style: italic;
  font-family: inherit;
}

.pd-sheet-textarea:focus { border-color: #f59e0b; }

.pd-sheet-save {
  flex: 2;
  background: linear-gradient(135deg, #d97706, #f59e0b);
  color: #000;
  border-radius: 12px;
  padding: 12px;
  text-align: center;
  font-size: 0.9rem;
  font-weight: 800;
  border: none;
  cursor: pointer;
}

.pd-sheet-cancel {
  flex: 1;
  background: var(--pd-card-inner);
  color: var(--pd-muted);
  border-radius: 12px;
  padding: 12px;
  text-align: center;
  font-size: 0.9rem;
  border: 1px solid var(--pd-border);
  cursor: pointer;
}

/* ── CTA button del plan card ── */
.pd-plan-cta {
  display: block;
  background: linear-gradient(135deg, #6d28d9, #4f46e5);
  color: #fff;
  border-radius: 12px;
  padding: 11px;
  text-align: center;
  font-size: 0.85rem;
  font-weight: 700;
  text-decoration: none;
  border: none;
  cursor: pointer;
}

/* ── Animación flash al actualizar ── */
@keyframes pd-flash-success {
  0%   { background: #166534; }
  100% { background: var(--pd-success-item); }
}

@keyframes pd-flash-error {
  0%   { background: #7f1d1d; }
  100% { background: var(--pd-danger-item); }
}

.pd-flash-success { animation: pd-flash-success 0.6s ease-out; }
.pd-flash-error   { animation: pd-flash-error   0.6s ease-out; }
```

- [ ] **Step 3: Verificar que el archivo queda bien enlazado**

```bash
bin/rails assets:precompile 2>&1 | grep -i "production\|error" | head -10
```

Esperado: sin errores relacionados con `production.css`.

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/production.css
git commit -m "feat: add production dark theme CSS foundation"
```

---

## Task 2: Backend — acción add_note

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/production/delivery_items_controller.rb`
- Modify: `app/policies/delivery_item_policy.rb`
- Create: `test/controllers/production/delivery_items_controller_test.rb`

- [ ] **Step 1: Escribir el test que debe fallar**

Crear `test/controllers/production/delivery_items_controller_test.rb`:

```ruby
require "test_helper"

class Production::DeliveryItemsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @item = delivery_items(:one)
    @user = users(:one)
    @user.update!(role: :logistics, email: "logistica@test.com",
                  password: "password123", password_confirmation: "password123")
    sign_in @user
  end

  test "add_note actualiza las notas del item via turbo_stream" do
    patch add_note_production_delivery_item_path(@item),
      params: { note: "Faltó en bodega" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "Faltó en bodega", @item.reload.notes
  end

  test "add_note requiere autenticación" do
    sign_out @user
    patch add_note_production_delivery_item_path(@item),
      params: { note: "cualquier cosa" }
    assert_response :redirect
  end
end
```

- [ ] **Step 2: Ejecutar el test para verificar que falla**

```bash
bin/rails test test/controllers/production/delivery_items_controller_test.rb
```

Esperado: falla con `ActionController::RoutingError` (ruta no existe aún).

- [ ] **Step 3: Agregar la ruta**

En `config/routes.rb`, dentro del bloque `resources :delivery_items` del namespace `production`, agregar `patch :add_note` al bloque `member`:

```ruby
resources :delivery_items do
  member do
    match :mark_loaded, via: [:get, :post]
    match :mark_unloaded, via: [:get, :post]
    match :mark_missing, via: [:get, :post]
    get   :reschedule_form
    patch :reschedule
    patch :add_note        # ← agregar esta línea
  end
end
```

- [ ] **Step 4: Agregar `add_note?` a la policy**

En `app/policies/delivery_item_policy.rb`, agregar después de `mark_missing?`:

```ruby
def add_note?
  admin_or_manager_or_logistics?
end
```

- [ ] **Step 5: Agregar la acción al controller**

En `app/controllers/production/delivery_items_controller.rb`, agregar antes del bloque `private`:

```ruby
def add_note
  authorize @delivery_item, :add_note?
  @delivery_item.update!(notes: params[:note].to_s.strip)

  respond_to do |format|
    format.html { redirect_back fallback_location: root_path }
    format.turbo_stream do
      render turbo_stream: turbo_stream.replace(
        "delivery_item_#{@delivery_item.id}",
        partial: "production/delivery_items/delivery_item_row",
        locals: { item: @delivery_item }
      )
    end
    format.json { render json: { success: true, notes: @delivery_item.notes } }
  end
end
```

- [ ] **Step 6: Ejecutar el test para verificar que pasa**

```bash
bin/rails test test/controllers/production/delivery_items_controller_test.rb
```

Esperado: `2 runs, 2 assertions, 0 failures, 0 errors`.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb \
        app/controllers/production/delivery_items_controller.rb \
        app/policies/delivery_item_policy.rb \
        test/controllers/production/delivery_items_controller_test.rb
git commit -m "feat: add add_note action to Production::DeliveryItemsController"
```

---

## Task 3: Rediseño de la pantalla índice

**Files:**
- Modify: `app/views/production/delivery_plans/index.html.erb`

- [ ] **Step 1: Reemplazar el contenido completo de `index.html.erb`**

```erb
<%# app/views/production/delivery_plans/index.html.erb %>
<div class="production-dark px-2 px-md-3 pb-5">

  <%# ── Header ── %>
  <div class="pd-header">
    <div class="d-flex justify-content-between align-items-start mb-3">
      <div>
        <h5 class="fw-bold mb-0 text-white">
          <i class="bi bi-truck me-2"></i>Bitácora de Carga
        </h5>
        <p class="mb-0" style="font-size:0.8rem;color:rgba(255,255,255,0.6);">
          <%= l @date, format: :long %>
        </p>
      </div>
    </div>
    <%# Navegación de fecha %>
    <div class="d-flex align-items-center gap-2">
      <%= link_to production_delivery_plans_path(date: @date - 1.day),
          class: "btn btn-sm d-flex align-items-center justify-content-center",
          style: "background:rgba(255,255,255,0.12);color:#fff;border:none;width:36px;height:36px;border-radius:10px;" do %>
        <i class="bi bi-chevron-left"></i>
      <% end %>
      <%= form_with url: production_delivery_plans_path, method: :get, class: "flex-grow-1" do %>
        <%= date_field_tag :date, @date,
            class: "form-control form-control-sm text-center fw-semibold",
            style: "background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.15);color:#fff;border-radius:10px;",
            onchange: "this.form.submit()" %>
      <% end %>
      <%= link_to production_delivery_plans_path(date: @date + 1.day),
          class: "btn btn-sm d-flex align-items-center justify-content-center",
          style: "background:rgba(255,255,255,0.12);color:#fff;border:none;width:36px;height:36px;border-radius:10px;" do %>
        <i class="bi bi-chevron-right"></i>
      <% end %>
      <%= link_to "Hoy", production_delivery_plans_path(date: Date.current),
          class: "btn btn-sm fw-bold",
          style: "background:#fff;color:#6d28d9;border-radius:10px;padding:6px 12px;" %>
    </div>
  </div>

  <% if @delivery_plans.empty? %>
    <%# ── Estado vacío ── %>
    <div class="text-center py-5 my-4">
      <i class="bi bi-calendar-x" style="font-size:3rem;color:#2d2d4e;"></i>
      <h6 class="mt-3 fw-semibold" style="color:#64748b;">Sin planes para esta fecha</h6>
      <p style="color:#475569;font-size:0.85rem;">No hay planes programados para el <%= l @date, format: :long %>.</p>
      <%= link_to "Ver hoy", production_delivery_plans_path(date: Date.current),
          class: "btn btn-sm mt-1",
          style: "border:1px solid #7c3aed;color:#a78bfa;border-radius:10px;" %>
    </div>

  <% else %>
    <%# ── Stats del día ── %>
    <%
      total_plans   = @delivery_plans.count
      loaded_plans  = @delivery_plans.count { |p| p.load_status == "all_loaded" }
      partial_plans = @delivery_plans.count { |p| p.load_status == "partial" }
      missing_plans = @delivery_plans.count { |p| p.load_status == "some_missing" }
    %>
    <div class="row g-2 my-3">
      <div class="col-3">
        <div class="pd-stat-cell">
          <div class="fw-bold fs-5" style="color:#94a3b8;"><%= total_plans %></div>
          <div style="font-size:0.7rem;color:#475569;">Planes</div>
        </div>
      </div>
      <div class="col-3">
        <div class="pd-stat-cell">
          <div class="fw-bold fs-5" style="color:#4ade80;"><%= loaded_plans %></div>
          <div style="font-size:0.7rem;color:#475569;">Completos</div>
        </div>
      </div>
      <div class="col-3">
        <div class="pd-stat-cell">
          <div class="fw-bold fs-5" style="color:#fbbf24;"><%= partial_plans %></div>
          <div style="font-size:0.7rem;color:#475569;">En progreso</div>
        </div>
      </div>
      <div class="col-3">
        <div class="pd-stat-cell">
          <div class="fw-bold fs-5" style="color:#f87171;"><%= missing_plans %></div>
          <div style="font-size:0.7rem;color:#475569;">Faltantes</div>
        </div>
      </div>
    </div>

    <%# ── Cards de planes ── %>
    <div class="d-flex flex-column gap-3">
      <% @delivery_plans.each do |plan| %>
        <% stats = plan.load_stats %>
        <%
          top_color = case plan.load_status
            when "all_loaded"   then "#22c55e"
            when "partial"      then "#f59e0b"
            when "some_missing" then "#ef4444"
            else "#475569"
          end
          pct_color = case plan.load_status
            when "all_loaded"   then "#4ade80"
            when "partial"      then "#fbbf24"
            when "some_missing" then "#f87171"
            else "#94a3b8"
          end
          badge_class = case plan.load_status
            when "all_loaded"   then "pd-badge--ok"
            when "partial"      then "pd-badge--partial"
            when "some_missing" then "pd-badge--missing"
            else "pd-badge--pending"
          end
          badge_label = case plan.load_status
            when "all_loaded"   then "Completo"
            when "partial"      then "En progreso"
            when "some_missing" then "Faltantes"
            else "Pendiente"
          end
          initials = plan.driver&.name&.split&.map { |w| w[0] }&.first(2)&.join&.upcase || "?"
        %>
        <div class="pd-card">
          <div class="pd-card-top" style="background:<%= top_color %>;"></div>
          <div class="p-3">
            <%# Header del card %>
            <div class="d-flex align-items-center gap-3 mb-3">
              <div class="pd-avatar" style="width:42px;height:42px;font-size:0.9rem;">
                <%= initials %>
              </div>
              <div class="flex-grow-1">
                <div class="fw-bold" style="font-size:0.95rem;"><%= plan.driver&.name || "Sin asignar" %></div>
                <div class="d-flex gap-2 mt-1 flex-wrap">
                  <span class="pd-badge pd-badge--pending">
                    <i class="bi bi-truck me-1"></i><%= plan.truck_label || "N/A" %>
                  </span>
                  <span class="pd-badge pd-badge--pending">#<%= plan.id %></span>
                </div>
              </div>
              <span class="pd-badge <%= badge_class %>"><%= badge_label %></span>
            </div>

            <%# Barra de progreso %>
            <div class="d-flex justify-content-between align-items-center mb-1">
              <small style="color:#64748b;font-size:0.72rem;">Progreso de carga</small>
              <span class="fw-bold" style="color:<%= pct_color %>;font-size:0.85rem;"><%= plan.load_percentage %>%</span>
            </div>
            <div class="pd-progress-wrap mb-3">
              <div class="pd-progress-bar" style="width:<%= plan.load_percentage %>%;background:<%= top_color %>;"></div>
            </div>

            <%# Mini stats %>
            <div class="row g-2 mb-3">
              <div class="col-4">
                <div class="pd-mini-stat">
                  <div class="fw-bold" style="color:#94a3b8;"><%= plan.deliveries.count %></div>
                  <div style="font-size:0.65rem;color:#475569;">Entregas</div>
                </div>
              </div>
              <div class="col-4">
                <div class="pd-mini-stat">
                  <div class="fw-bold" style="color:#4ade80;"><%= stats[:loaded_items] %></div>
                  <div style="font-size:0.65rem;color:#475569;">Cargados</div>
                </div>
              </div>
              <div class="col-4">
                <div class="pd-mini-stat">
                  <div class="fw-bold" style="color:<%= stats[:missing_items] > 0 ? '#f87171' : '#94a3b8' %>;">
                    <%= stats[:missing_items] %>
                  </div>
                  <div style="font-size:0.65rem;color:#475569;">Faltantes</div>
                </div>
              </div>
            </div>

            <%# CTA %>
            <% cta_style, cta_label = case plan.load_status
              when "all_loaded"
                ["background:linear-gradient(135deg,#166534,#16a34a);",
                 "<i class='bi bi-check-circle me-2'></i>Ver bitácora completa"]
              when "some_missing"
                ["background:linear-gradient(135deg,#7f1d1d,#b91c1c);",
                 "<i class='bi bi-exclamation-triangle me-2'></i>Revisar faltantes"]
              else
                ["background:linear-gradient(135deg,#6d28d9,#4f46e5);",
                 "<i class='bi bi-clipboard-check me-2'></i>Abrir Bitácora"]
              end
            %>
            <%= link_to loading_production_delivery_plan_path(plan),
                class: "pd-plan-cta",
                style: cta_style do %>
              <%= cta_label.html_safe %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Verificar en el navegador**

```bash
bin/rails server
```

Abrir `http://localhost:3000/production/delivery_plans`. Verificar:
- Fondo oscuro
- Cards con franja de color
- Stats del día visibles
- Botón CTA cambia según el estado

- [ ] **Step 3: Commit**

```bash
git add app/views/production/delivery_plans/index.html.erb
git commit -m "feat: redesign production delivery plans index with dark theme"
```

---

## Task 4: Partial `_plan_header.html.erb`

**Files:**
- Modify: `app/views/production/delivery_plans/_plan_header.html.erb`

**Nota:** Este partial es reemplazado via Turbo Stream con `id="plan_header"`. El wrapper con ese ID vive en `loading.html.erb`. Este partial es solo el contenido interior.

- [ ] **Step 1: Reemplazar el contenido**

```erb
<%# app/views/production/delivery_plans/_plan_header.html.erb %>
<%
  top_color = case delivery_plan.load_status
    when "all_loaded"   then "#22c55e"
    when "partial"      then "#f59e0b"
    when "some_missing" then "#ef4444"
    else "#475569"
  end
  pct_color = case delivery_plan.load_status
    when "all_loaded"   then "#4ade80"
    when "partial"      then "#fbbf24"
    when "some_missing" then "#f87171"
    else "#94a3b8"
  end
  badge_class = case delivery_plan.load_status
    when "all_loaded"   then "pd-badge--ok"
    when "partial"      then "pd-badge--partial"
    when "some_missing" then "pd-badge--missing"
    else "pd-badge--pending"
  end
  badge_label = case delivery_plan.load_status
    when "all_loaded"   then "Completo"
    when "partial"      then "En progreso"
    when "some_missing" then "Faltantes"
    else "Pendiente"
  end
  initials = delivery_plan.driver&.name&.split&.map { |w| w[0] }&.first(2)&.join&.upcase || "?"
%>
<div class="pd-header">
  <%# Fila superior: atrás + avatar + nombre + badge %>
  <div class="d-flex align-items-center gap-3 mb-3">
    <%= link_to production_delivery_plans_path(date: delivery_plan.first_delivery_date || Date.current),
        class: "d-flex align-items-center justify-content-center flex-shrink-0",
        style: "background:rgba(255,255,255,0.12);color:#fff;width:34px;height:34px;border-radius:10px;text-decoration:none;" do %>
      <i class="bi bi-chevron-left"></i>
    <% end %>
    <div class="pd-avatar flex-shrink-0" style="width:40px;height:40px;font-size:0.9rem;">
      <%= initials %>
    </div>
    <div class="flex-grow-1 min-width-0">
      <div class="fw-bold text-white text-truncate" style="font-size:0.95rem;">
        <%= delivery_plan.driver&.name || "Sin asignar" %>
      </div>
      <div style="font-size:0.72rem;color:rgba(255,255,255,0.6);">
        <i class="bi bi-truck me-1"></i><%= delivery_plan.truck_label || "N/A" %>
        &nbsp;·&nbsp;Plan #<%= delivery_plan.id %>
        &nbsp;·&nbsp;Sem. <%= delivery_plan.week %>/<%= delivery_plan.year %>
      </div>
    </div>
    <span class="pd-badge <%= badge_class %> flex-shrink-0"><%= badge_label %></span>
  </div>

  <%# Barra de progreso %>
  <div class="d-flex justify-content-between align-items-center mb-1">
    <small style="color:rgba(255,255,255,0.55);font-size:0.72rem;">Progreso de carga del plan</small>
    <span class="fw-bold" style="color:<%= pct_color %>;font-size:0.95rem;"><%= delivery_plan.load_percentage %>%</span>
  </div>
  <div class="pd-progress-wrap mb-3">
    <div class="pd-progress-bar" style="width:<%= delivery_plan.load_percentage %>%;background:<%= top_color %>;"></div>
  </div>

  <%# Stats row: 4 celdas %>
  <div class="row g-2">
    <div class="col-3">
      <div style="background:rgba(255,255,255,0.08);border-radius:10px;padding:6px 4px;text-align:center;">
        <div class="fw-bold" style="color:#94a3b8;font-size:1rem;"><%= load_stats[:total_items] %></div>
        <div style="font-size:0.65rem;color:rgba(255,255,255,0.4);">Total</div>
      </div>
    </div>
    <div class="col-3">
      <div style="background:rgba(255,255,255,0.08);border-radius:10px;padding:6px 4px;text-align:center;">
        <div class="fw-bold" style="color:#4ade80;font-size:1rem;"><%= load_stats[:loaded_items] %></div>
        <div style="font-size:0.65rem;color:rgba(255,255,255,0.4);">Cargados</div>
      </div>
    </div>
    <div class="col-3">
      <div style="background:rgba(255,255,255,0.08);border-radius:10px;padding:6px 4px;text-align:center;">
        <div class="fw-bold" style="color:#fbbf24;font-size:1rem;"><%= load_stats[:unloaded_items] %></div>
        <div style="font-size:0.65rem;color:rgba(255,255,255,0.4);">Pendientes</div>
      </div>
    </div>
    <div class="col-3">
      <div style="background:rgba(255,255,255,0.08);border-radius:10px;padding:6px 4px;text-align:center;">
        <div class="fw-bold" style="color:#f87171;font-size:1rem;"><%= load_stats[:missing_items] %></div>
        <div style="font-size:0.65rem;color:rgba(255,255,255,0.4);">Faltantes</div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/production/delivery_plans/_plan_header.html.erb
git commit -m "feat: redesign plan header partial with dark gradient and stats row"
```

---

## Task 5: Partial `_load_summary.html.erb`

**Files:**
- Modify: `app/views/production/delivery_plans/_load_summary.html.erb`

**Nota:** El Turbo Stream en `DeliveryItemsController#render_item_update_streams` reemplaza `id="load_summary"`. Ese wrapper vive en `loading.html.erb`. Este partial es su contenido.

- [ ] **Step 1: Reemplazar el contenido**

```erb
<%# app/views/production/delivery_plans/_load_summary.html.erb %>
<div class="px-2 py-2" style="background:#12122a;border-bottom:1px solid #2d2d4e;">
  <div class="d-flex justify-content-between align-items-center mb-2">
    <small class="fw-semibold" style="color:#64748b;font-size:0.72rem;text-transform:uppercase;letter-spacing:0.5px;">
      <i class="bi bi-box-seam me-1"></i>Resumen de productos
    </small>
    <% if policy(delivery_plan).mark_all_loaded? %>
      <%= button_to mark_all_loaded_production_delivery_plan_path(delivery_plan),
          method: :post,
          class: "btn btn-sm fw-bold",
          style: "background:#166534;color:#4ade80;border:none;border-radius:8px;font-size:0.72rem;padding:4px 10px;",
          data: { turbo_confirm: "¿Marcar TODOS los productos del plan como cargados?" } do %>
        <i class="bi bi-check-all me-1"></i>Marcar todo
      <% end %>
    <% end %>
  </div>
  <div class="row g-2">
    <div class="col-3">
      <div class="pd-mini-stat">
        <div class="fw-bold" style="color:#94a3b8;font-size:1rem;"><%= load_stats[:total_items] %></div>
        <div style="font-size:0.65rem;color:#475569;">Total</div>
      </div>
    </div>
    <div class="col-3">
      <div class="pd-mini-stat">
        <div class="fw-bold" style="color:#4ade80;font-size:1rem;"><%= load_stats[:loaded_items] %></div>
        <div style="font-size:0.65rem;color:#475569;">Cargados</div>
      </div>
    </div>
    <div class="col-3">
      <div class="pd-mini-stat">
        <div class="fw-bold" style="color:#fbbf24;font-size:1rem;"><%= load_stats[:unloaded_items] %></div>
        <div style="font-size:0.65rem;color:#475569;">Pendientes</div>
      </div>
    </div>
    <div class="col-3">
      <div class="pd-mini-stat">
        <div class="fw-bold" style="color:<%= load_stats[:missing_items] > 0 ? '#f87171' : '#94a3b8' %>;font-size:1rem;">
          <%= load_stats[:missing_items] %>
        </div>
        <div style="font-size:0.65rem;color:#475569;">Faltantes</div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/production/delivery_plans/_load_summary.html.erb
git commit -m "feat: redesign load summary partial with dark mini stats"
```

---

## Task 6: Loading page wrapper + bottom sheet element

**Files:**
- Modify: `app/views/production/delivery_plans/loading.html.erb`

- [ ] **Step 1: Reemplazar el contenido completo**

```erb
<%# app/views/production/delivery_plans/loading.html.erb %>
<div class="production-dark"
     data-controller="loading"
     data-loading-plan-id-value="<%= @delivery_plan.id %>">

  <%# ── Header sticky (Turbo Stream target: plan_header) ── %>
  <div id="plan_header" class="sticky-top" style="top:56px;z-index:100;">
    <%= render "plan_header", delivery_plan: @delivery_plan, load_stats: @load_stats %>
  </div>

  <%# ── Resumen de productos (Turbo Stream target: load_summary) ── %>
  <div id="load_summary">
    <%= render "load_summary", delivery_plan: @delivery_plan, load_stats: @load_stats %>
  </div>

  <%# ── Barra de búsqueda ── %>
  <div class="pd-search-wrap" style="position:relative;">
    <i class="bi bi-search pd-search-icon"></i>
    <input type="text"
           class="pd-search-input"
           placeholder="Buscar cliente o pedido..."
           data-action="input->loading#filterDeliveries"
           data-loading-target="searchInput"
           value="<%= @filter_search %>">
  </div>

  <%# ── Chips de filtro ── %>
  <div class="pd-filter-bar">
    <%
      chip_filters = [
        { value: "",             label: "Todos",      css: "pd-chip--all"     },
        { value: "empty",        label: "Sin cargar", css: "pd-chip--unloaded"},
        { value: "partial",      label: "Parcial",    css: "pd-chip--partial" },
        { value: "all_loaded",   label: "Cargado",    css: "pd-chip--loaded"  },
        { value: "some_missing", label: "Faltantes",  css: "pd-chip--missing" },
      ]
    %>
    <% chip_filters.each do |chip| %>
      <% active = @filter_load_status.to_s == chip[:value] %>
      <%= link_to loading_production_delivery_plan_path(@delivery_plan,
                    load_status: chip[:value], search: @filter_search),
          class: "pd-chip #{active ? chip[:css] : 'pd-chip--unloaded'}",
          data: { turbo_action: "replace" } do %>
        <%= chip[:label] %>
      <% end %>
    <% end %>
  </div>

  <%# ── Lista de entregas ── %>
  <div id="delivery_cards_list"
       class="px-2 pb-5 pt-2 d-flex flex-column gap-3"
       data-loading-target="deliveryList">
    <% if @assignments.empty? %>
      <div class="text-center py-5">
        <i class="bi bi-inbox" style="font-size:2.5rem;color:#2d2d4e;"></i>
        <p class="mt-3" style="color:#64748b;">No hay entregas que coincidan.</p>
        <%= link_to "Ver todas", loading_production_delivery_plan_path(@delivery_plan),
            class: "btn btn-sm mt-1",
            style: "border:1px solid #7c3aed;color:#a78bfa;border-radius:10px;" %>
      </div>
    <% else %>
      <% @assignments.each do |assignment| %>
        <%= render "production/deliveries/delivery_card",
            delivery: assignment.delivery,
            assignment: assignment %>
      <% end %>
    <% end %>
  </div>

  <%# ── Bottom sheet de notas (gestionado por note-sheet controller) ── %>
  <div id="pd-note-sheet-container"
       data-controller="note-sheet"
       data-note-sheet-save-url-value="">
    <div class="pd-sheet-overlay"
         data-action="click->note-sheet#close"></div>
    <div class="pd-sheet">
      <div class="pd-sheet-handle"></div>
      <div class="d-flex justify-content-between align-items-start mb-2">
        <h6 class="fw-bold mb-0 text-white">
          <i class="bi bi-chat-left-text me-2"></i>Nota del producto
        </h6>
        <button class="btn p-0" style="color:#64748b;font-size:1.1rem;background:none;border:none;"
                data-action="click->note-sheet#close">
          <i class="bi bi-x-lg"></i>
        </button>
      </div>
      <div class="pd-sheet-product mb-3" data-note-sheet-target="productLabel">
        Producto
      </div>
      <label class="d-block mb-1" style="font-size:0.72rem;color:#64748b;text-transform:uppercase;letter-spacing:0.5px;">
        Observación
      </label>
      <textarea class="pd-sheet-textarea"
                data-note-sheet-target="textarea"
                placeholder="Escribe una nota..."></textarea>
      <div class="d-flex gap-2 mt-3">
        <button class="pd-sheet-cancel" data-action="click->note-sheet#close">Cancelar</button>
        <button class="pd-sheet-save" data-action="click->note-sheet#save">
          <i class="bi bi-floppy me-1"></i>Guardar nota
        </button>
      </div>
    </div>
  </div>

</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/production/delivery_plans/loading.html.erb
git commit -m "feat: redesign loading page with dark theme, filter chips, and note sheet"
```

---

## Task 7: Partial `_delivery_card.html.erb`

**Files:**
- Modify: `app/views/production/deliveries/_delivery_card.html.erb`

- [ ] **Step 1: Reemplazar el contenido completo**

```erb
<%# app/views/production/deliveries/_delivery_card.html.erb %>
<%
  top_color = case delivery.load_status
    when "all_loaded"   then "#22c55e"
    when "partial"      then "#f59e0b"
    when "some_missing" then "#ef4444"
    else "#475569"
  end
  stop_num = assignment&.stop_order || "?"
  stop_badge_class = case delivery.load_status
    when "all_loaded" then "pd-stop-badge--done"
    when nil, "empty" then "pd-stop-badge--pending"
    else ""
  end
%>
<div id="delivery_<%= delivery.id %>"
     class="pd-card"
     data-client-name="<%= delivery.client&.name&.downcase %>"
     data-order-number="<%= delivery.order&.number&.downcase %>"
     data-loading-target="deliveryCard">

  <%# Franja de color en el tope %>
  <div class="pd-card-top" style="background:<%= top_color %>;"></div>

  <%# Header colapsable %>
  <div class="pd-del-hdr"
       data-bs-toggle="collapse"
       data-bs-target="#delivery_items_<%= delivery.id %>"
       aria-expanded="<%= delivery.load_status == 'all_loaded' ? 'false' : 'true' %>">
    <div class="pd-stop-badge <%= stop_badge_class %>"><%= stop_num %></div>
    <div class="flex-grow-1 min-width-0">
      <div class="fw-bold text-truncate" style="font-size:0.9rem;color:#f1f5f9;">
        <%= delivery.client&.name %>
      </div>
      <div class="text-truncate" style="font-size:0.75rem;color:#64748b;">
        <i class="bi bi-geo-alt me-1"></i><%= delivery.delivery_address&.address&.truncate(45) %>
      </div>
    </div>
    <div class="d-flex align-items-center gap-2 flex-shrink-0 ms-2">
      <%# Mini progress bar %>
      <div style="width:36px;height:5px;background:#0f0f1a;border-radius:3px;overflow:hidden;">
        <div style="height:100%;width:<%= delivery.load_percentage %>%;background:<%= top_color %>;border-radius:3px;"></div>
      </div>
      <%# Badge count %>
      <% loaded = delivery.delivery_items.count { |i| i.load_status == "loaded" } %>
      <% total  = delivery.delivery_items.count %>
      <span class="pd-badge <%= top_color == '#22c55e' ? 'pd-badge--ok' : (top_color == '#ef4444' ? 'pd-badge--missing' : 'pd-badge--partial') %>">
        <%= loaded %>/<%= total %>
      </span>
      <i class="bi bi-chevron-down" style="color:#475569;font-size:0.8rem;"></i>
    </div>
  </div>

  <%# Items colapsables (cerrado si está completamente cargado) %>
  <div id="delivery_items_<%= delivery.id %>"
       class="collapse <%= delivery.load_status == 'all_loaded' ? '' : 'show' %>">

    <% delivery.delivery_items.each do |item| %>
      <div id="delivery_item_<%= item.id %>">
        <%= render "production/delivery_items/delivery_item_row", item: item %>
      </div>
    <% end %>

    <%# Footer con acciones masivas %>
    <div class="pd-card-footer">
      <% if policy(delivery).mark_all_loaded? %>
        <%= button_to mark_all_loaded_production_delivery_path(delivery),
            method: :post,
            class: "pd-btn-all",
            data: { turbo_confirm: "¿Marcar todos los productos de esta entrega como cargados?" } do %>
          <i class="bi bi-check-all me-1"></i>Marcar todo cargado
        <% end %>
      <% end %>
      <% if policy(delivery).reset_load_status? %>
        <%= button_to reset_load_status_production_delivery_path(delivery),
            method: :post,
            class: "pd-btn-reset",
            title: "Resetear carga",
            data: { turbo_confirm: "¿Resetear el estado de carga?" } do %>
          <i class="bi bi-arrow-counterclockwise"></i>
        <% end %>
      <% end %>
    </div>
  </div>

</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/production/deliveries/_delivery_card.html.erb
git commit -m "feat: redesign delivery card partial with collapsible dark theme"
```

---

## Task 8: Partial `_delivery_item_row.html.erb`

**Files:**
- Modify: `app/views/production/delivery_items/_delivery_item_row.html.erb`

- [ ] **Step 1: Reemplazar el contenido completo**

```erb
<%# app/views/production/delivery_items/_delivery_item_row.html.erb %>
<%
  row_class = case item.load_status
    when "loaded"  then "pd-item-row--loaded"
    when "missing" then "pd-item-row--missing"
    else ""
  end
  badge_class = case item.load_status
    when "loaded"  then "pd-badge--ok"
    when "missing" then "pd-badge--missing"
    else nil
  end
  badge_label = case item.load_status
    when "loaded"  then "<i class='bi bi-check-circle-fill me-1'></i>Cargado"
    when "missing" then "<i class='bi bi-exclamation-triangle-fill me-1'></i>Faltante"
    else nil
  end
  note_btn_class = item.notes.present? ? "pd-btn-note--active" : ""
%>
<div class="pd-item-row <%= row_class %>"
     data-controller="delivery-item"
     data-delivery-item-item-id-value="<%= item.id %>"
     data-delivery-item-delivery-id-value="<%= item.delivery_id %>"
     data-delivery-item-status-value="<%= item.load_status %>"
     data-delivery-item-note-value="<%= item.notes.to_s %>"
     data-delivery-item-product-value="<%= item.order_item&.product_name&.to_s %>"
     data-delivery-item-save-note-url-value="<%= add_note_production_delivery_item_path(item) %>">

  <%# Info del producto %>
  <div class="d-flex justify-content-between align-items-start gap-2 mb-2">
    <div class="flex-grow-1 min-width-0">
      <div class="fw-bold text-truncate" style="font-size:0.9rem;color:#f1f5f9;">
        <%= item.order_item&.product_name || "Producto sin nombre" %>
      </div>
      <div class="d-flex flex-wrap gap-2 mt-1" style="font-size:0.75rem;color:#64748b;">
        <span><i class="bi bi-layers me-1"></i>×<%= item.quantity %></span>
        <% if item.service_case? %>
          <span class="pd-badge pd-badge--partial">
            <i class="bi bi-tools me-1"></i>Caso de servicio
          </span>
        <% end %>
      </div>
      <%# Preview de nota en amarillo %>
      <% if item.notes.present? %>
        <div class="pd-note-preview" data-delivery-item-target="notePreview">
          <i class="bi bi-chat-left-text me-1"></i><%= item.notes.truncate(50) %>
        </div>
      <% else %>
        <div class="pd-note-preview" data-delivery-item-target="notePreview" style="display:none;"></div>
      <% end %>
    </div>
    <%# Badge de estado %>
    <span data-delivery-item-target="badge" class="pd-badge <%= badge_class %> flex-shrink-0">
      <%= badge_label&.html_safe %>
    </span>
  </div>

  <%# Botones de acción ── mínimo 44px de altura ── %>
  <div class="d-flex gap-2" data-delivery-item-target="buttons">
    <% if item.load_status == "loaded" %>
      <%# Estado: cargado — mostrar desmarcar %>
      <% if policy(item).mark_unloaded? %>
        <%= link_to mark_unloaded_production_delivery_item_path(item),
            class: "pd-btn-undo",
            data: { action: "click->delivery-item#markUnloaded" } do %>
          <i class="bi bi-arrow-counterclockwise me-1"></i>Desmarcar
        <% end %>
      <% end %>
      <% if policy(item).add_note? %>
        <button class="pd-btn-note pd-btn-note--loaded"
                data-action="click->delivery-item#openNoteSheet">
          <i class="bi bi-chat-left-text"></i>
        </button>
      <% end %>

    <% elsif item.load_status == "missing" %>
      <%# Estado: faltante — mostrar cargar + desmarcar %>
      <% if policy(item).mark_loaded? %>
        <%= link_to mark_loaded_production_delivery_item_path(item),
            class: "pd-btn-ok",
            data: { action: "click->delivery-item#markLoaded" } do %>
          <i class="bi bi-check-lg me-1"></i>Cargado
        <% end %>
      <% end %>
      <% if policy(item).mark_unloaded? %>
        <%= link_to mark_unloaded_production_delivery_item_path(item),
            class: "pd-btn-undo",
            style: "flex:1;",
            data: { action: "click->delivery-item#markUnloaded" } do %>
          <i class="bi bi-arrow-counterclockwise me-1"></i>Desmarcar
        <% end %>
      <% end %>
      <% if policy(item).add_note? %>
        <button class="pd-btn-note <%= note_btn_class %>"
                data-action="click->delivery-item#openNoteSheet">
          <i class="bi bi-chat-left-text"></i>
        </button>
      <% end %>

    <% else %>
      <%# Estado: pendiente — mostrar cargado + faltante %>
      <% if policy(item).mark_loaded? %>
        <%= link_to mark_loaded_production_delivery_item_path(item),
            class: "pd-btn-ok",
            data: { action: "click->delivery-item#markLoaded" } do %>
          <i class="bi bi-check-lg me-1"></i>Cargado
        <% end %>
      <% end %>
      <% if policy(item).mark_missing? %>
        <%= link_to mark_missing_production_delivery_item_path(item),
            class: "pd-btn-miss",
            data: { action: "click->delivery-item#markMissing" } do %>
          <i class="bi bi-x-lg me-1"></i>Faltante
        <% end %>
      <% end %>
      <% if policy(item).add_note? %>
        <button class="pd-btn-note <%= note_btn_class %>"
                data-action="click->delivery-item#openNoteSheet">
          <i class="bi bi-chat-left-text"></i>
        </button>
      <% end %>
    <% end %>
  </div>

</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/production/delivery_items/_delivery_item_row.html.erb
git commit -m "feat: redesign delivery item row with large touch buttons and note preview"
```

---

## Task 9: JS — `delivery_item_controller.js`

**Files:**
- Modify: `app/javascript/controllers/delivery_item_controller.js`

- [ ] **Step 1: Reemplazar el archivo completo**

```javascript
// app/javascript/controllers/delivery_item_controller.js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["badge", "buttons", "notePreview"]
  static values  = {
    itemId:      Number,
    deliveryId:  Number,
    status:      String,
    note:        String,
    product:     String,
    saveNoteUrl: String,
  }

  connect() {}

  async markLoaded(event) {
    event.preventDefault()
    this._setLoading()
    try {
      const response = await this._submit(event.currentTarget.href, "POST")
      if (response.ok) {
        this._applyStatus("loaded")
        this._dispatchUpdate("loaded")
      } else {
        this._setError()
      }
    } catch {
      this._setError()
    }
  }

  async markUnloaded(event) {
    event.preventDefault()
    this._setLoading()
    try {
      const response = await this._submit(event.currentTarget.href, "POST")
      if (response.ok) {
        this._applyStatus("unloaded")
        this._dispatchUpdate("unloaded")
      } else {
        this._setError()
      }
    } catch {
      this._setError()
    }
  }

  async markMissing(event) {
    event.preventDefault()
    // Sin confirm() — el botón ↺ Desmarcar sirve como undo
    this._setLoading()
    try {
      const response = await this._submit(event.currentTarget.href, "POST")
      if (response.ok) {
        this._applyStatus("missing")
        this._dispatchUpdate("missing")
      } else {
        this._setError()
      }
    } catch {
      this._setError()
    }
  }

  openNoteSheet(event) {
    event.preventDefault()
    // Dispatchar evento al note-sheet controller (vive en loading.html.erb)
    document.dispatchEvent(new CustomEvent("delivery-item:open-note-sheet", {
      detail: {
        itemId:      this.itemIdValue,
        product:     this.productValue,
        note:        this.noteValue,
        saveUrl:     this.saveNoteUrlValue,
        controller:  this,
      }
    }))
  }

  // Llamado por note_sheet_controller después de guardar exitosamente
  noteUpdated(newNote) {
    this.noteValue = newNote
    if (this.hasNotePreviewTarget) {
      if (newNote.trim()) {
        this.notePreviewTarget.innerHTML =
          `<i class="bi bi-chat-left-text me-1"></i>${this._escapeHtml(newNote.substring(0, 50))}${newNote.length > 50 ? "…" : ""}`
        this.notePreviewTarget.style.display = ""
      } else {
        this.notePreviewTarget.textContent = ""
        this.notePreviewTarget.style.display = "none"
      }
    }
    // Actualizar color del botón de nota
    const noteBtn = this.element.querySelector("[data-action*='openNoteSheet']")
    if (noteBtn) {
      noteBtn.classList.toggle("pd-btn-note--active", newNote.trim().length > 0)
    }
  }

  // ── Privados ──

  async _submit(url, method) {
    const csrfToken = document.querySelector("[name='csrf-token']").content
    const response = await fetch(url, {
      method,
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
      },
      credentials: "same-origin",
    })
    const contentType = response.headers.get("Content-Type") || ""
    if (contentType.includes("turbo-stream")) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
    }
    return response
  }

  _setLoading() {
    this._disableButtons()
    if (this.hasBadgeTarget) {
      this.badgeTarget.innerHTML =
        '<span class="spinner-border spinner-border-sm me-1"></span>'
      this.badgeTarget.className = "pd-badge pd-badge--pending"
    }
  }

  _applyStatus(status) {
    this.statusValue = status
    this._enableButtons()
    this._updateBadge(status)
    this._updateRowBackground(status)
    this.element.classList.add("pd-flash-success")
    setTimeout(() => this.element.classList.remove("pd-flash-success"), 600)
  }

  _setError() {
    this._enableButtons()
    if (this.hasBadgeTarget) {
      this.badgeTarget.innerHTML = '<i class="bi bi-exclamation-circle me-1"></i>Error'
      this.badgeTarget.className = "pd-badge pd-badge--missing"
    }
    this.element.classList.add("pd-flash-error")
    setTimeout(() => {
      this.element.classList.remove("pd-flash-error")
      this._updateBadge(this.statusValue)
    }, 2000)
  }

  _updateBadge(status) {
    if (!this.hasBadgeTarget) return
    const configs = {
      loaded:  { cls: "pd-badge pd-badge--ok",      html: "<i class='bi bi-check-circle-fill me-1'></i>Cargado"                     },
      missing: { cls: "pd-badge pd-badge--missing",  html: "<i class='bi bi-exclamation-triangle-fill me-1'></i>Faltante"            },
      unloaded:{ cls: "pd-badge",                    html: "" },
    }
    const cfg = configs[status] || configs.unloaded
    this.badgeTarget.className = cfg.cls
    this.badgeTarget.innerHTML = cfg.html
  }

  _updateRowBackground(status) {
    this.element.classList.remove("pd-item-row--loaded", "pd-item-row--missing")
    if (status === "loaded")  this.element.classList.add("pd-item-row--loaded")
    if (status === "missing") this.element.classList.add("pd-item-row--missing")
  }

  _disableButtons() {
    if (this.hasButtonsTarget) {
      this.buttonsTarget.querySelectorAll("a, button").forEach(el => {
        el.classList.add("disabled")
        el.setAttribute("aria-disabled", "true")
      })
    }
  }

  _enableButtons() {
    if (this.hasButtonsTarget) {
      this.buttonsTarget.querySelectorAll("a, button").forEach(el => {
        el.classList.remove("disabled")
        el.removeAttribute("aria-disabled")
      })
    }
  }

  _dispatchUpdate(status) {
    this.element.dispatchEvent(new CustomEvent("delivery-item:updated", {
      detail: { itemId: this.itemIdValue, deliveryId: this.deliveryIdValue, status },
      bubbles: true,
    }))
  }

  _escapeHtml(str) {
    return str.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/delivery_item_controller.js
git commit -m "feat: update delivery_item_controller with dark theme support and no confirm()"
```

---

## Task 10: JS — nuevo `note_sheet_controller.js`

**Files:**
- Create: `app/javascript/controllers/note_sheet_controller.js`

- [ ] **Step 1: Crear el archivo**

```javascript
// app/javascript/controllers/note_sheet_controller.js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets  = ["textarea", "productLabel"]
  static values   = { saveUrl: String }

  connect() {
    this._activeItemController = null
    this._onOpenBound = this._onOpen.bind(this)
    document.addEventListener("delivery-item:open-note-sheet", this._onOpenBound)
  }

  disconnect() {
    document.removeEventListener("delivery-item:open-note-sheet", this._onOpenBound)
  }

  close() {
    this.element.classList.remove("pd-sheet-open")
    this._activeItemController = null
  }

  async save() {
    const note     = this.textareaTarget.value.trim()
    const saveUrl  = this.saveUrlValue
    const csrfToken= document.querySelector("[name='csrf-token']").content

    const saveBtn = this.element.querySelector(".pd-sheet-save")
    if (saveBtn) {
      saveBtn.disabled = true
      saveBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span>Guardando...'
    }

    try {
      const response = await fetch(saveUrl, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "text/vnd.turbo-stream.html",
        },
        credentials: "same-origin",
        body: new URLSearchParams({ note }),
      })

      const contentType = response.headers.get("Content-Type") || ""
      if (response.ok) {
        if (contentType.includes("turbo-stream")) {
          const html = await response.text()
          Turbo.renderStreamMessage(html)
        }
        // Notificar al item controller para actualizar el preview
        if (this._activeItemController) {
          this._activeItemController.noteUpdated(note)
        }
        this.close()
      } else {
        this._showSaveError(saveBtn)
      }
    } catch {
      this._showSaveError(saveBtn)
    }
  }

  // ── Privados ──

  _onOpen(event) {
    const { product, note, saveUrl, controller } = event.detail
    this._activeItemController = controller
    this.saveUrlValue = saveUrl
    if (this.hasProductLabelTarget) {
      this.productLabelTarget.textContent = product || "Producto"
    }
    if (this.hasTextareaTarget) {
      this.textareaTarget.value = note || ""
      // Foco después de que el panel termina la animación
      setTimeout(() => this.textareaTarget.focus(), 260)
    }
    this.element.classList.add("pd-sheet-open")
    // Reiniciar botón de guardar
    const saveBtn = this.element.querySelector(".pd-sheet-save")
    if (saveBtn) {
      saveBtn.disabled = false
      saveBtn.innerHTML = '<i class="bi bi-floppy me-1"></i>Guardar nota'
    }
  }

  _showSaveError(saveBtn) {
    if (saveBtn) {
      saveBtn.disabled = false
      saveBtn.innerHTML = '<i class="bi bi-exclamation-circle me-1"></i>Error — Reintentar'
      saveBtn.style.background = "linear-gradient(135deg,#7f1d1d,#b91c1c)"
      saveBtn.style.color = "#fca5a5"
    }
  }
}
```

- [ ] **Step 2: Verificar que Stimulus registra el controller automáticamente**

```bash
grep -r "eagerLoadControllersFrom\|application.register\|note.sheet\|note_sheet" app/javascript/
```

Si el proyecto usa `eagerLoadControllersFrom`, el controller se registra solo al estar en `controllers/`. Si usa registro manual, agregar:

```javascript
// en app/javascript/controllers/index.js o application.js:
import NoteSheetController from "./note_sheet_controller"
application.register("note-sheet", NoteSheetController)
```

- [ ] **Step 3: Smoke test en el navegador**

1. Abrir la bitácora de un plan con entregas
2. Tocar el botón <i class="bi bi-chat-left-text"></i> en cualquier ítem
3. Verificar que el bottom sheet sube con animación
4. Escribir una nota y tocar "Guardar nota"
5. Verificar que el preview amarillo aparece bajo el nombre del producto
6. Verificar que el overlay oscuro cierra el sheet al tocarlo

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/note_sheet_controller.js
git commit -m "feat: add note_sheet_controller for bottom sheet note UX"
```

---

## Verificación final

- [ ] **Revisar Turbo Stream updates**

Marcar un ítem como cargado y verificar que:
1. El fondo del ítem cambia a verde oscuro (`pd-item-row--loaded`)
2. La barra de progreso del header (`id="plan_header"`) se actualiza
3. El resumen de productos (`id="load_summary"`) se actualiza

- [ ] **Verificar tema oscuro en index**

Navegar a `/production/delivery_plans` y confirmar:
1. Fondo `#0f0f1a` en toda la página
2. Cards con franja de color semántica
3. CTA cambia color según estado del plan

- [ ] **Verificar mobile**

Abrir Chrome DevTools → Toggle device toolbar → iPhone 12 Pro (390px):
1. Botones de ítem son fácilmente tocables (mínimo 44px)
2. Header sticky visible al hacer scroll
3. Bottom sheet ocupa el ancho completo

- [ ] **Commit final de limpieza si hay archivos residuales**

```bash
git status
git add -p   # revisar todo lo pendiente
git commit -m "chore: cleanup production revamp leftovers"
```
