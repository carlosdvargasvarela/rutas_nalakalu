# CSS Centralización + Production Light Theme — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidar todo el CSS de la app en un único pipeline SCSS con variables globales, y reemplazar el tema oscuro del módulo production por uno claro coherente con el resto de la app.

**Architecture:** `application.bootstrap.scss` es el único punto de entrada compilado por `yarn build:css`. Los archivos `.css` sueltos (actualmente muertos o ausentes del browser) se convierten a partials `.scss` e importados desde ahí. Las variables de color se definen como CSS custom properties en `:root` dentro de `_variables.scss`. El módulo production migra de `.production-dark` a `.production-light` manteniendo la misma estructura táctil (botones 44px, cards colapsables, bottom sheet).

**Tech Stack:** SCSS (Dart Sass CLI), Bootstrap 5.3, Bootstrap Icons, PostCSS/Autoprefixer, Rails + cssbundling-rails

**Compile command:** `yarn build:css`

---

## File Map

**Crear:**
- `app/assets/stylesheets/_variables.scss`
- `app/assets/stylesheets/_production_light.scss`
- `app/assets/stylesheets/_components.scss`
- `app/assets/stylesheets/_deliveries.scss`
- `app/assets/stylesheets/_notifications.scss`
- `app/assets/stylesheets/_searchable_select.scss`
- `app/assets/stylesheets/_status_system.scss`
- `app/assets/stylesheets/_production.scss`

**Modificar:**
- `app/assets/stylesheets/application.bootstrap.scss`
- `app/assets/stylesheets/_delivery_plans.scss` (append delivery_plans.css content)
- `app/views/production/delivery_plans/index.html.erb`
- `app/views/production/delivery_plans/loading.html.erb`
- ~20 vistas con inline styles (Tasks 10–11)

**Eliminar (tras migración):**
- `app/assets/stylesheets/delivery.css`
- `app/assets/stylesheets/delivery_cards.css`
- `app/assets/stylesheets/delivery_detail.css`
- `app/assets/stylesheets/delivery_plans.css`
- `app/assets/stylesheets/delivery_plans.scss` (sin underscore)
- `app/assets/stylesheets/components.css`
- `app/assets/stylesheets/workspace.css`
- `app/assets/stylesheets/searchable_select.css`
- `app/assets/stylesheets/status_system.css`
- `app/assets/stylesheets/notifications.css`
- `app/assets/stylesheets/production.scss`
- `app/assets/stylesheets/_production_dark.scss`
- `app/assets/stylesheets/dashboard.css` (100% duplicado — solo borrar)
- `app/assets/stylesheets/dashboard.css.backup`

---

## Task 1: Variables globales + actualizar entry point

**Files:**
- Create: `app/assets/stylesheets/_variables.scss`
- Modify: `app/assets/stylesheets/application.bootstrap.scss`

- [ ] **Step 1: Crear `_variables.scss`**

```scss
// app/assets/stylesheets/_variables.scss
:root {
  // ── Brand ─────────────────────────────────────────────
  --color-brand-primary:    #0d6efd;
  --color-brand-accent:     #6610f2;
  --color-brand-bg:         #fff7ee;

  // ── Surface ───────────────────────────────────────────
  --color-surface:          #ffffff;
  --color-surface-subtle:   #f8f9fa;
  --color-border:           #dee2e6;

  // ── Text ──────────────────────────────────────────────
  --color-text:             #212529;
  --color-text-muted:       #6c757d;

  // ── Status ────────────────────────────────────────────
  --color-success:          #198754;
  --color-success-subtle:   #d1e7dd;
  --color-danger:           #dc3545;
  --color-danger-subtle:    #f8d7da;
  --color-warning:          #856404;
  --color-warning-subtle:   #fff3cd;

  // ── Production module ─────────────────────────────────
  --pd-accent:              var(--color-brand-primary);
  --pd-surface:             var(--color-surface);
  --pd-surface-subtle:      var(--color-surface-subtle);
  --pd-border:              var(--color-border);
  --pd-success-item:        #f0fdf4;
  --pd-danger-item:         #fff5f5;
  --pd-warning-item:        #fffbeb;
  --pd-note-text:           #664d03;
}
```

- [ ] **Step 2: Agregar `@import "variables"` al inicio de `application.bootstrap.scss`**

El archivo actual empieza con `@import "bootstrap/scss/bootstrap"`. Agregar la línea de variables DESPUÉS de los imports de Bootstrap (para que Bootstrap no sobreescriba las custom properties):

```scss
// app/assets/stylesheets/application.bootstrap.scss
@import "bootstrap/scss/bootstrap";
@import "bootstrap-icons/font/bootstrap-icons";
@import "variables";
@import "navbar";
@import "notifications";
@import "dashboard";
@import "devise_sessions";
@import "application";
@import "delivery_plans";
@import "production_dark";
// Estilos globales para consistencia
body {
  background-color: #fff7ee !important;
  &.bg-light {
    background-color: #fff7ee !important;
  }
}
```

- [ ] **Step 3: Verificar compilación**

```bash
yarn build:css
```

Esperado: sin errores. El archivo `app/assets/builds/application.css` se regenera. Verificar que contiene `:root {` con las variables.

```bash
grep -c "color-brand-primary" app/assets/builds/application.css
```

Esperado: `1`

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/_variables.scss app/assets/stylesheets/application.bootstrap.scss
git commit -m "feat: add _variables.scss with CSS custom properties for future rebrand"
```

---

## Task 2: Crear tema claro del módulo Production

**Files:**
- Create: `app/assets/stylesheets/_production_light.scss`

- [ ] **Step 1: Crear `_production_light.scss`**

```scss
/* ============================================================
   PRODUCTION MODULE — Light Theme
   Scope: .production-light wrapper en todas las vistas production/
   ============================================================ */

.production-light {
  --pd-bg:            #f8f9fa;
  --pd-card:          #ffffff;
  --pd-card-inner:    #f8f9fa;
  --pd-border:        #dee2e6;
  --pd-accent:        var(--color-brand-primary, #0d6efd);
  --pd-text:          #212529;
  --pd-muted:         #6c757d;
  --pd-success-text:  #198754;
  --pd-success-bg:    #d1e7dd;
  --pd-success-item:  #f0fdf4;
  --pd-danger-text:   #dc3545;
  --pd-danger-bg:     #f8d7da;
  --pd-danger-item:   #fff5f5;
  --pd-warning-text:  #856404;
  --pd-warning-bg:    #fff3cd;
  --pd-warning-item:  #fffbeb;
  --pd-note-text:     #664d03;

  background: var(--pd-bg);
  min-height: 100vh;
  color: var(--pd-text);
}

.pd-header {
  background: linear-gradient(135deg, #0d6efd 0%, #6610f2 100%);
  padding: 14px 16px 16px;
}

.pd-card {
  background: var(--pd-card);
  border: 1px solid var(--pd-border);
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
}

.pd-card-top {
  height: 3px;
  width: 100%;
}

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

.pd-progress-wrap {
  height: 9px;
  background: #e9ecef;
  border-radius: 5px;
  overflow: hidden;
}

.pd-progress-bar {
  height: 100%;
  border-radius: 5px;
  transition: width 0.3s ease;
  background: #0d6efd;
}

.pd-badge {
  font-size: 0.7rem;
  padding: 3px 10px;
  border-radius: 20px;
  font-weight: 700;
  display: inline-block;
}

.pd-badge--ok      { background: #d1e7dd; color: #198754; }
.pd-badge--missing { background: #f8d7da; color: #dc3545; }
.pd-badge--partial { background: #fff3cd; color: #856404; }
.pd-badge--pending { background: #f8f9fa; color: #6c757d; border: 1px solid #dee2e6; }

.pd-avatar {
  border-radius: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 800;
  color: #fff;
  flex-shrink: 0;
  background: linear-gradient(135deg, #0d6efd, #6610f2);
}

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

.pd-chip--all     { background: #0d6efd; color: #fff; }
.pd-chip--unloaded{ background: #f8f9fa; color: #6c757d; border-color: #dee2e6; }
.pd-chip--partial { background: #fff3cd; color: #856404; border-color: rgba(255,193,7,0.27); }
.pd-chip--loaded  { background: #d1e7dd; color: #198754; border-color: rgba(25,135,84,0.27); }
.pd-chip--missing { background: #f8d7da; color: #dc3545; border-color: rgba(220,53,69,0.27); }

.pd-search-wrap {
  background: var(--pd-card-inner);
  padding: 8px 12px 10px;
  position: relative;
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
.pd-search-input:focus {
  border-color: #0d6efd;
  box-shadow: 0 0 0 3px rgba(13, 110, 253, 0.15);
}

.pd-search-icon {
  position: absolute;
  left: 22px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--pd-muted);
  font-size: 0.875rem;
  pointer-events: none;
}

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
  background: #0d6efd;
  color: #fff;
  font-size: 0.75rem;
  font-weight: 800;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.pd-stop-badge--done    { background: #d1e7dd; color: #198754; }
.pd-stop-badge--pending { background: #f0f0f0; color: #6c757d; }

.pd-item-row {
  padding: 10px 14px;
  border-bottom: 1px solid var(--pd-card-inner);
  background: var(--pd-card);
}

.pd-item-row:last-child { border-bottom: none; }
.pd-item-row--loaded  { background: #f0fdf4; }
.pd-item-row--missing { background: #fff5f5; }

.pd-btn-ok {
  flex: 3;
  background: #198754;
  color: #fff;
  border-radius: 11px;
  padding: 11px 0;
  text-align: center;
  font-size: 0.8rem;
  font-weight: 800;
  border: none;
  cursor: pointer;
  text-decoration: none;
  display: block;
  min-height: 44px;
}

.pd-btn-miss {
  flex: 3;
  background: #fff5f5;
  color: #dc3545;
  border-radius: 11px;
  padding: 11px 0;
  text-align: center;
  font-size: 0.8rem;
  font-weight: 700;
  border: 1px solid #f8d7da;
  cursor: pointer;
  text-decoration: none;
  display: block;
  min-height: 44px;
}

.pd-btn-undo {
  flex: 2;
  background: #f8f9fa;
  color: #6c757d;
  border-radius: 11px;
  padding: 11px 0;
  text-align: center;
  font-size: 0.75rem;
  border: 1px solid #dee2e6;
  cursor: pointer;
  text-decoration: none;
  display: block;
  min-height: 44px;
}

.pd-btn-note {
  width: 44px;
  background: #f8f9fa;
  color: #6c757d;
  border-radius: 11px;
  padding: 11px 0;
  text-align: center;
  font-size: 1rem;
  border: 1px solid #dee2e6;
  cursor: pointer;
  display: block;
  flex-shrink: 0;
  min-height: 44px;
}

.pd-btn-note--active { color: #664d03; border-color: rgba(255,193,7,0.27); background: #fffbeb; }
.pd-btn-note--loaded { color: #198754; border-color: rgba(25,135,84,0.27); }

.pd-card-footer {
  border-top: 1px solid #dee2e6;
  padding: 8px 14px;
  display: flex;
  gap: 8px;
  background: #f8f9fa;
}

.pd-btn-all {
  flex: 1;
  background: #d1e7dd;
  color: #198754;
  border-radius: 10px;
  padding: 8px;
  text-align: center;
  font-size: 0.75rem;
  font-weight: 700;
  border: 1px solid #a3cfbb;
  cursor: pointer;
}

.pd-btn-reset {
  background: #f8f9fa;
  color: #6c757d;
  border-radius: 10px;
  padding: 8px 12px;
  text-align: center;
  font-size: 0.8rem;
  border: 1px solid #dee2e6;
  cursor: pointer;
}

.pd-note-preview {
  font-size: 0.72rem;
  color: #664d03;
  font-style: italic;
  margin-top: 3px;
}

.pd-sheet-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
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
  background: #ffffff;
  border-radius: 24px 24px 0 0;
  padding: 12px 20px 32px;
  box-shadow: 0 -4px 24px rgba(0, 0, 0, 0.12);
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
  background: #dee2e6;
  border-radius: 2px;
  margin: 0 auto 14px;
}

.pd-sheet-product {
  font-size: 0.8rem;
  color: #0d6efd;
  background: rgba(13, 110, 253, 0.08);
  padding: 5px 10px;
  border-radius: 8px;
  display: inline-block;
  margin-bottom: 12px;
}

.pd-sheet-textarea {
  width: 100%;
  background: #fffbeb;
  border: 1px solid #ffc107;
  border-radius: 12px;
  color: #664d03;
  font-size: 0.9rem;
  padding: 12px;
  resize: none;
  height: 90px;
  outline: none;
  font-style: italic;
  font-family: inherit;
}

.pd-sheet-textarea:focus {
  border-color: #ffc107;
  box-shadow: 0 0 0 3px rgba(255, 193, 7, 0.2);
}

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
  background: #f8f9fa;
  color: #6c757d;
  border-radius: 12px;
  padding: 12px;
  text-align: center;
  font-size: 0.9rem;
  border: 1px solid #dee2e6;
  cursor: pointer;
}

.pd-plan-cta {
  display: block;
  background: linear-gradient(135deg, #0d6efd, #6610f2);
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

@keyframes pd-flash-success {
  0%   { background: #d1e7dd; }
  100% { background: #f0fdf4; }
}

@keyframes pd-flash-error {
  0%   { background: #f8d7da; }
  100% { background: #fff5f5; }
}

.pd-flash-success { animation: pd-flash-success 0.6s ease-out; }
.pd-flash-error   { animation: pd-flash-error   0.6s ease-out; }
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/_production_light.scss
git commit -m "feat: add _production_light.scss with light tactile theme for production module"
```

---

## Task 3: Actualizar vistas production (dark → light)

**Files:**
- Modify: `app/views/production/delivery_plans/index.html.erb`
- Modify: `app/views/production/delivery_plans/loading.html.erb`

Solo 2 archivos tienen la clase `production-dark`. Los partials (`_delivery_card.html.erb`, `_delivery_item_row.html.erb`, etc.) no tienen el wrapper y no necesitan cambio — heredan las variables del wrapper del padre.

- [ ] **Step 1: Reemplazar `production-dark` por `production-light` en ambas vistas**

```bash
grep -n "production-dark" app/views/production/delivery_plans/index.html.erb
grep -n "production-dark" app/views/production/delivery_plans/loading.html.erb
```

En cada línea encontrada, cambiar `class="production-dark"` (o `"... production-dark ..."`) por `class="production-light"` (o el equivalente con las otras clases presentes).

- [ ] **Step 2: Verificar que no quedan referencias al tema oscuro**

```bash
grep -r "production-dark" app/views/
```

Esperado: sin output.

- [ ] **Step 3: Commit**

```bash
git add app/views/production/delivery_plans/index.html.erb \
        app/views/production/delivery_plans/loading.html.erb
git commit -m "feat: migrate production views from dark to light theme"
```

---

## Task 4: Crear `_components.scss`

Consolida: `workspace.css` + `components.css` + utilidades genéricas de `delivery.css` + overrides globales de Bootstrap desde `production.scss`.

**Nota sobre conflictos:** `delivery.css` y `workspace.css` ambos definen `#delivery_detail` y `.btn-xs`. Se usa la versión de `workspace.css` (animación cubic-bezier, `.btn-xs` más detallado). La versión de `delivery.css` se descarta.

**Files:**
- Create: `app/assets/stylesheets/_components.scss`

- [ ] **Step 1: Crear `_components.scss`**

```scss
// app/assets/stylesheets/_components.scss
// Workspace layout, summary cards, utilidades genéricas

// ── Workspace layout ──────────────────────────────────────────
#delivery_detail {
  animation: slideInRight 0.35s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes slideInRight {
  from { opacity: 0; transform: translateX(30px); }
  to   { opacity: 1; transform: translateX(0); }
}

.workspace-container {
  height: calc(100vh - 65px);
  overflow: hidden;
  background-color: #f8f9fa;
}

.scroll-panel {
  overflow-y: auto;
  scrollbar-width: thin;
}
.scroll-panel::-webkit-scrollbar { width: 4px; }
.scroll-panel::-webkit-scrollbar-thumb { background: #cbd5e0; border-radius: 10px; }

.detail-panel-body {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
}

.detail-header { flex-shrink: 0; }
.detail-tabs   { flex-shrink: 0; }
.detail-footer { flex-shrink: 0; }

.detail-tab-content {
  flex: 1 1 0;
  min-height: 0;
  overflow: hidden;
}

.detail-tab-content .tab-pane {
  height: 100%;
  overflow-y: auto;
  padding: 1rem 1.25rem;
  scrollbar-width: thin;
  box-sizing: border-box;
}
.detail-tab-content .tab-pane::-webkit-scrollbar { width: 4px; }
.detail-tab-content .tab-pane::-webkit-scrollbar-thumb { background: #cbd5e0; border-radius: 10px; }

.product-table-workspace { width: 100%; }
.product-table-workspace .table { table-layout: fixed; width: 100%; }
.product-table-workspace thead.sticky-top th {
  background-color: #fff;
  box-shadow: 0 1px 0 #dee2e6;
}
.product-table-workspace tbody tr { animation: fadeInRow 0.25s ease-out both; }

@keyframes fadeInRow {
  from { opacity: 0; transform: translateY(4px); }
  to   { opacity: 1; transform: translateY(0); }
}

.item-with-notes {
  background-color: #fffbeb;
  transition: background-color 0.2s ease;
}
.item-with-notes:hover { background-color: #fff3cd !important; }

// ── Utility button ────────────────────────────────────────────
.btn-xs {
  padding: 2px 8px;
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.3px;
}

// ── Scrollbars globales ───────────────────────────────────────
.overflow-auto::-webkit-scrollbar { width: 6px; }
.overflow-auto::-webkit-scrollbar-thumb { background: #ccc; border-radius: 10px; }

// ── Turbo ─────────────────────────────────────────────────────
.turbo-progress-bar { background-color: #0d6efd; }

// ── Summary cards v2 ─────────────────────────────────────────
.summary-card-v2 {
  background: #ffffff;
  border: 1px solid #eef2f6;
  border-radius: 12px;
  overflow: hidden;
  height: 100%;
  display: flex;
  flex-direction: column;
}

.summary-card-v2 .card-header-v2 {
  background-color: #f8fafc;
  border-bottom: 1px solid #eef2f6;
  padding: 10px 16px;
  font-size: 0.7rem;
  font-weight: 800;
  text-transform: uppercase;
  color: #64748b;
  letter-spacing: 0.05em;
  display: flex;
  align-items: center;
  gap: 8px;
}

.summary-card-v2 .card-body-v2 { padding: 16px; }

.info-row-v2 {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  margin-bottom: 12px;
}
.info-row-v2:last-child { margin-bottom: 0; }

.info-icon-v2 {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  font-size: 1rem;
}

.info-content-v2 .info-label-v2 {
  font-size: 0.65rem;
  font-weight: 700;
  color: #94a3b8;
  margin-bottom: 2px;
}
.info-content-v2 .info-value-v2 {
  font-size: 0.85rem;
  font-weight: 600;
  color: #1e293b;
  line-height: 1.2;
}

// ── Bootstrap global overrides ────────────────────────────────
.card {
  transition: box-shadow 0.3s ease;

  &:hover {
    box-shadow: 0 0.5rem 1rem rgba(0, 0, 0, 0.15) !important;
  }
}

.progress-bar { transition: width 0.6s ease; }

.btn.disabled,
.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/_components.scss
git commit -m "feat: add _components.scss consolidating workspace, summary cards, and global overrides"
```

---

## Task 5: Crear `_deliveries.scss`

Consolida: `delivery_cards.css` + `delivery_detail.css`.

**Nota:** `delivery.css` también tenía `#delivery_detail` y `.btn-xs` pero ya están en `_components.scss`. El único contenido único de `delivery.css` que no se duplicó ya está cubierto por los otros archivos.

**Files:**
- Create: `app/assets/stylesheets/_deliveries.scss`

- [ ] **Step 1: Crear `_deliveries.scss`**

```scss
// app/assets/stylesheets/_deliveries.scss
// Delivery card list + detail panel visual styles

// ── Delivery cards (lista) ────────────────────────────────────
.delivery-card-link {
  display: block;
  text-decoration: none;
  transition: all 0.2s ease;
  margin-bottom: 8px;
}

.delivery-card {
  transition: all 0.2s ease;
  border: 1px solid #edf2f7;
  border-radius: 12px !important;
}
.delivery-card:hover {
  transform: scale(1.01);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05) !important;
}

.active-card .delivery-card {
  background-color: #f0f7ff !important;
  border-color: #3b82f6 !important;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.15) !important;
}

.delivery-card .card-title {
  color: #1a202c;
  font-weight: 700;
  font-size: 0.95rem;
}

// ── Detail panel (visual) ─────────────────────────────────────
.detail-header {
  background: linear-gradient(135deg, #ffffff 0%, #f8faff 100%);
}

.detail-meta {
  font-size: 0.78rem;
  color: #64748b;
}
.detail-meta span {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.detail-tabs .nav-link {
  font-size: 0.82rem;
  font-weight: 500;
  color: #64748b;
  padding: 0.6rem 0.75rem;
  border-bottom: 2px solid transparent;
  transition: color 0.2s, border-color 0.2s;
}
.detail-tabs .nav-link:hover  { color: var(--bs-primary); }
.detail-tabs .nav-link.active {
  color: var(--bs-primary);
  font-weight: 700;
  border-bottom-color: var(--bs-primary);
}

.detail-notes  { border-radius: 8px; }

.detail-footer {
  background-color: #f8f9fa;
  font-size: 0.78rem;
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/_deliveries.scss
git commit -m "feat: add _deliveries.scss consolidating delivery card and detail panel styles"
```

---

## Task 6: Completar `_delivery_plans.scss`

El `_delivery_plans.scss` existente tiene 10 líneas (solo responsive del mapa). Appendear el contenido de `delivery_plans.css` (drag-and-drop sortable) que nunca estuvo en el pipeline.

**Files:**
- Modify: `app/assets/stylesheets/_delivery_plans.scss`

- [ ] **Step 1: Appendear estilos sortable al `_delivery_plans.scss` existente**

Agregar al final del archivo (después del contenido actual):

```scss

// ── Sortable / drag-and-drop ──────────────────────────────────
.dragging-group {
  opacity: 0.5;
  background-color: #e3f2fd !important;
  border-left: 4px solid #2196f3 !important;
}

.sortable-ghost {
  opacity: 0.4;
  background-color: #bbdefb !important;
}

.sortable-chosen {
  background-color: #e3f2fd !important;
  cursor: grabbing !important;
}

.sortable-drag {
  opacity: 1 !important;
  background-color: #fff !important;
  box-shadow: 0 5px 15px rgba(0, 0, 0, 0.3) !important;
}

.drag-handle {
  cursor: grab;
  transition: color 0.2s;
}
.drag-handle:hover  { color: #0d6efd !important; }
.drag-handle:active { cursor: grabbing; }

.stop-group-header { border-left: 4px solid #0d6efd; }

.stop-item.table-active {
  background-color: #f8f9fa;
  border-left: 3px solid #6c757d;
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/_delivery_plans.scss
git commit -m "feat: add sortable drag-and-drop styles to _delivery_plans.scss"
```

---

## Task 7: Crear `_notifications.scss`, `_searchable_select.scss`, `_status_system.scss`

**Files:**
- Create: `app/assets/stylesheets/_notifications.scss`
- Create: `app/assets/stylesheets/_searchable_select.scss`
- Create: `app/assets/stylesheets/_status_system.scss`

`_notifications.scss` reemplaza a `notifications.css` que actualmente es importado por Sass como CSS. Al existir `_notifications.scss`, el `@import "notifications"` resolverá al partial sin necesidad de cambiar `application.bootstrap.scss`.

- [ ] **Step 1: Crear `_notifications.scss`**

```scss
// app/assets/stylesheets/_notifications.scss
// Página de notificaciones (notification-item, notification-content)

.notification-item {
  transition: all 0.2s ease;
}
.notification-item:hover { background-color: #f8f9fa !important; }

.notification-content { line-height: 1.6; }
.notification-content p { margin-bottom: 0.5rem; }
.notification-content p:last-child { margin-bottom: 0; }

.card-header { border-bottom: none; }

.notification-meta { opacity: 0.8; }

@media (max-width: 768px) {
  .notification-item { padding: 1rem !important; }
  .notification-item .row { flex-direction: column; }
  .notification-item .col-md-4 { margin-top: 1rem; text-align: left !important; }
}

@keyframes pulse-light {
  0%   { background-color: #e3f2fd; }
  50%  { background-color: #f8f9fa; }
  100% { background-color: #f8f9fa; }
}
.bg-light { animation: pulse-light 2s ease-in-out; }
```

- [ ] **Step 2: Crear `_searchable_select.scss`**

```scss
// app/assets/stylesheets/_searchable_select.scss
// Componente searchable-select (Stimulus controller)

.ss-trigger {
  cursor: pointer;
  min-height: 38px;
  user-select: none;
  background-color: #fff;
}
.ss-trigger.disabled {
  background-color: #e9ecef;
  pointer-events: none;
  opacity: 0.65;
}
.ss-trigger:focus {
  outline: 0;
  border-color: #86b7fe;
  box-shadow: 0 0 0 0.25rem rgba(13, 110, 253, 0.25);
}

.ss-option {
  cursor: pointer;
  transition: background-color 0.1s;
}
.ss-option:hover,
.ss-option.ss-active  { background-color: var(--bs-primary-bg-subtle); }
.ss-option.ss-selected { background-color: var(--bs-primary-bg-subtle); }

.ss-search:focus {
  box-shadow: none;
  border-color: #dee2e6 !important;
}
```

- [ ] **Step 3: Crear `_status_system.scss`**

```scss
// app/assets/stylesheets/_status_system.scss
// Bordes laterales semánticos y badges de estado

.state-border-warning   { border-left: 4px solid var(--bs-warning)   !important; }
.state-border-primary   { border-left: 4px solid var(--bs-primary)   !important; }
.state-border-success   { border-left: 4px solid var(--bs-success)   !important; }
.state-border-danger    { border-left: 4px solid var(--bs-danger)    !important; }
.state-border-info      { border-left: 4px solid var(--bs-info)      !important; }
.state-border-dark      { border-left: 4px solid var(--bs-dark)      !important; }
.state-border-secondary { border-left: 4px solid var(--bs-secondary) !important; }

.status-badge-soft {
  font-weight: 600;
  letter-spacing: 0.02em;
  padding: 0.35em 0.8em;
  text-transform: uppercase;
  font-size: 0.65rem;
}
```

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/_notifications.scss \
        app/assets/stylesheets/_searchable_select.scss \
        app/assets/stylesheets/_status_system.scss
git commit -m "feat: add _notifications, _searchable_select, _status_system partials"
```

---

## Task 8: Crear `_production.scss`

Extrae de `production.scss` solo los estilos específicos del módulo production (flash animations, toast). Los overrides globales (`.card:hover`, `.progress-bar`, `.btn.disabled`) ya van en `_components.scss` (Task 4).

**Files:**
- Create: `app/assets/stylesheets/_production.scss`

- [ ] **Step 1: Crear `_production.scss`**

```scss
// app/assets/stylesheets/_production.scss
// Feedback visual del módulo production: flash, toast, spinner

@keyframes flash-success {
  0%, 100% { background-color: transparent; }
  50%       { background-color: rgba(25, 135, 84, 0.2); }
}

@keyframes flash-error {
  0%, 100% { background-color: transparent; }
  50%       { background-color: rgba(220, 53, 69, 0.2); }
}

@keyframes highlight-flash {
  0%, 100% { box-shadow: none; }
  50%       { box-shadow: 0 0 20px rgba(13, 110, 253, 0.6); }
}

.flash-success   { animation: flash-success   1s ease-in-out; }
.flash-error     { animation: flash-error     1s ease-in-out; }
.highlight-flash { animation: highlight-flash 2s ease-in-out; }

.toast-notification {
  position: fixed;
  top: 20px;
  right: 20px;
  min-width: 300px;
  max-width: 500px;
  padding: 16px 20px;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  display: flex;
  align-items: center;
  justify-content: space-between;
  z-index: 9999;
  opacity: 0;
  transform: translateX(400px);
  transition: all 0.3s ease-in-out;

  &.show           { opacity: 1; transform: translateX(0); }
  &.toast-success  { background-color: #d1e7dd; border-left: 4px solid #198754; color: #0f5132; }
  &.toast-error    { background-color: #f8d7da; border-left: 4px solid #dc3545; color: #842029; }
  &.toast-warning  { background-color: #fff3cd; border-left: 4px solid #ffc107; color: #664d03; }
  &.toast-info     { background-color: #cff4fc; border-left: 4px solid #0dcaf0; color: #055160; }

  .toast-content {
    display: flex;
    align-items: center;
    flex: 1;
    i { font-size: 1.2rem; }
  }

  .toast-close {
    background: none;
    border: none;
    color: inherit;
    opacity: 0.6;
    cursor: pointer;
    padding: 0;
    margin-left: 12px;
    &:hover { opacity: 1; }
  }
}

.btn .spinner-border-sm {
  width: 0.875rem;
  height: 0.875rem;
  border-width: 0.15em;
}

@media (max-width: 576px) {
  .toast-notification {
    top: 10px;
    right: 10px;
    left: 10px;
    min-width: auto;
    max-width: none;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/_production.scss
git commit -m "feat: add _production.scss with flash and toast feedback styles"
```

---

## Task 9: Actualizar `application.bootstrap.scss` + eliminar archivos huérfanos

**Files:**
- Modify: `app/assets/stylesheets/application.bootstrap.scss`
- Delete: 14 archivos huérfanos

- [ ] **Step 1: Reemplazar contenido completo de `application.bootstrap.scss`**

```scss
// app/assets/stylesheets/application.bootstrap.scss
@import "bootstrap/scss/bootstrap";
@import "bootstrap-icons/font/bootstrap-icons";
@import "variables";
@import "navbar";
@import "notifications";
@import "dashboard";
@import "devise_sessions";
@import "application";
@import "components";
@import "searchable_select";
@import "status_system";
@import "deliveries";
@import "delivery_plans";
@import "production";
@import "production_light";

body {
  background-color: #fff7ee !important;

  &.bg-light {
    background-color: #fff7ee !important;
  }
}
```

**Nota:** Se elimina `@import "production_dark"` y se agrega `production`, `components`, `searchable_select`, `status_system`, `deliveries`, `production_light`. `_mixins.scss` y `_animations.scss` NO se importan aquí — ya lo hace `_dashboard.scss` y duplicarlos agregaría `@keyframes` duplicados al output.

- [ ] **Step 2: Compilar y verificar**

```bash
yarn build:css
```

Esperado: sin errores.

```bash
grep -c "workspace-container\|ss-trigger\|state-border-warning\|delivery-card-link\|pd-btn-ok\|production-light" app/assets/builds/application.css
```

Esperado: `6` (una clase de cada grupo, confirma que todos los nuevos partials están compilados).

- [ ] **Step 3: Eliminar archivos huérfanos**

```bash
rm app/assets/stylesheets/delivery.css
rm app/assets/stylesheets/delivery_cards.css
rm app/assets/stylesheets/delivery_detail.css
rm app/assets/stylesheets/delivery_plans.css
rm app/assets/stylesheets/delivery_plans.scss
rm app/assets/stylesheets/components.css
rm app/assets/stylesheets/workspace.css
rm app/assets/stylesheets/searchable_select.css
rm app/assets/stylesheets/status_system.css
rm app/assets/stylesheets/notifications.css
rm app/assets/stylesheets/production.scss
rm app/assets/stylesheets/_production_dark.scss
rm app/assets/stylesheets/dashboard.css
rm app/assets/stylesheets/dashboard.css.backup
```

- [ ] **Step 4: Compilar de nuevo y verificar que nada se rompe**

```bash
yarn build:css
```

Esperado: sin errores. El output debe ser idéntico al del Step 2.

- [ ] **Step 5: Commit**

```bash
git add -A app/assets/stylesheets/
git commit -m "refactor: centralize CSS pipeline — all styles through application.bootstrap.scss"
```

---

## Task 10: Extraer inline styles — vistas prioritarias

Las 5 vistas con más ocurrencias de `style=`. Regla: solo extraer `style=` con valores estáticos (sin `<%= %>`). Los `style=` dinámicos quedan inline.

**Files (prioridad):**
- `app/views/deliveries/show_partials/_summary_cards.html.erb` (31)
- `app/views/driver/delivery_plans/index.html.erb` (26)
- `app/views/production/delivery_plans/index.html.erb` (24)
- `app/views/deliveries/index_partials/_delivery_card_content.html.erb` (22)
- `app/views/delivery_plans/edit_partials/_stops.html.erb` (16)

**Metodología para cada vista:**

- [ ] **Step 1: Por cada vista, identificar inline styles estáticos**

```bash
grep -n 'style="[^"]*"' app/views/deliveries/show_partials/_summary_cards.html.erb | grep -v '<%='
```

Filtrar los que no tienen `<%=` (esos son estáticos y candidatos a extraer).

- [ ] **Step 2: Agrupar por patrón**

Agrupar las ocurrencias similares en clases nombradas. Ejemplos de patrones comunes a buscar:
- `style="font-size: X"` → crear `.text-Xpx` o usar clase Bootstrap si aplica
- `style="color: #XYZ"` → crear clase semántica en el archivo SCSS del módulo
- `style="min-width: Xpx"` → crear clase utilitaria
- `style="background: linear-gradient(...)"` → crear clase de componente

Poner las clases nuevas en el archivo SCSS del dominio:
- `_summary_cards.html.erb` → `_deliveries.scss`
- `driver/delivery_plans/index.html.erb` → `_delivery_plans.scss`
- `production/delivery_plans/index.html.erb` → `_production_light.scss`
- `_delivery_card_content.html.erb` → `_deliveries.scss`
- `edit_partials/_stops.html.erb` → `_delivery_plans.scss`

- [ ] **Step 3: Por cada estilo extraído, actualizar la vista y el SCSS**

Patrón de reemplazo (ejemplo):
```html
<!-- Antes -->
<div style="min-width: 80px; text-align: center; font-weight: 700;">

<!-- Después -->
<div class="stat-value-cell">
```

```scss
// En el SCSS correspondiente:
.stat-value-cell {
  min-width: 80px;
  text-align: center;
  font-weight: 700;
}
```

- [ ] **Step 4: Compilar tras cada vista completada**

```bash
yarn build:css
```

Esperado: sin errores.

- [ ] **Step 5: Commit por cada vista procesada**

```bash
git add app/views/deliveries/show_partials/_summary_cards.html.erb \
        app/assets/stylesheets/_deliveries.scss
git commit -m "refactor: extract inline styles from _summary_cards into _deliveries.scss"
```

Repetir Steps 1–5 para las 4 vistas restantes.

---

## Task 11: Extraer inline styles — vistas secundarias

Las 15 vistas con menos de 16 ocurrencias. Misma metodología que Task 10.

**Files:**

| Vista | Destino SCSS |
|---|---|
| `audit_logs/index.html.erb` | `_components.scss` |
| `audit_logs/_related_version_compact.html.erb` | `_components.scss` |
| `notifications/_notification.html.erb` | `_notifications.scss` |
| `client_notes/_modal.html.erb` | `_components.scss` |
| `client_notes/_note.html.erb` | `_components.scss` |
| `client_notes/_pinned_banner.html.erb` | `_components.scss` |
| `deliveries/show_partials/_history.html.erb` | `_deliveries.scss` |
| `deliveries/show_partials/_alerts.html.erb` | `_deliveries.scss` |
| `shared/_timeline.html.erb` | `_components.scss` |
| `dashboard/_pending_tasks.html.erb` | `_dashboard.scss` |
| `clients/index.html.erb` | `_components.scss` |
| `public_trackings/show.html.erb` | `_components.scss` |
| `admin/maintenance_windows/new.html.erb` | `_components.scss` |
| `admin/maintenance_windows/show.html.erb` | `_components.scss` |
| `admin/quickbooks/show.html.erb` | `_components.scss` |

- [ ] **Step 1: Por cada vista, aplicar la metodología del Task 10 (Steps 1–5)**

Recordar: no tocar `app/views/*_mailer/` — los mailers requieren inline styles para email clients.

- [ ] **Step 2: Verificación final**

```bash
yarn build:css
grep -r 'style="[^"]*"' app/views/ --include="*.erb" \
  --exclude-dir={"admin_reports_mailer,seller_reports_mailer,seller_delivery_summary_mailer"} \
  | grep -v '<%=' | wc -l
```

Confirmar que el número es significativamente menor que el baseline original (~200+).

- [ ] **Step 3: Commit final**

```bash
git add app/assets/stylesheets/ app/views/
git commit -m "refactor: extract remaining inline styles into SCSS partials"
```
