# CSS: Centralización + Tema Claro para Production

**Fecha:** 2026-05-22  
**Supersede:** La decisión de tema oscuro en `2026-05-22-production-delivery-plans-revamp-design.md` § 2 y § 7.  
**Alcance:** Todo el CSS/SCSS de la app — archivos sueltos, inline styles en vistas no-mailer, y módulo production.

---

## 1. Contexto y objetivo

La app tiene CSS disperso en tres lugares: archivos `.css` sueltos fuera del pipeline SCSS, `style=` inline en vistas, y partials `.scss` no importados. Esto dificulta aplicar la paleta de empresa en el futuro y genera inconsistencias visuales.

El módulo `production/` usa tema oscuro que desentona con el resto de la app (fondo crema `#fff7ee`, Bootstrap claro). Se reemplaza por un tema claro con el mismo nivel de usabilidad táctil.

**Objetivo:** único punto de entrada CSS (`application.bootstrap.scss`), variables globales preparadas para rebrand, y módulo production integrado visualmente con la app.

---

## 2. Arquitectura SCSS

`application.bootstrap.scss` es el único archivo que genera output. Todo lo demás son partials con `_` prefix.

```
app/assets/stylesheets/
├── application.bootstrap.scss   ← entrada única
├── _variables.scss              ← NUEVO
├── _mixins.scss
├── _animations.scss
├── _navbar.scss
├── _devise_sessions.scss
├── _notifications.scss          ← fusión de notifications.css + partial existente
├── _searchable_select.scss      ← desde searchable_select.css
├── _status_system.scss          ← desde status_system.css
├── _components.scss             ← fusión de components.css + workspace.css
├── _deliveries.scss             ← fusión de delivery.css + delivery_cards.css + delivery_detail.css
├── _delivery_plans.scss         ← fusión de delivery_plans.css + delivery_plans.scss
├── _dashboard.scss              ← existente (ya importa sub-partials)
├── _production.scss             ← toast + flash animations (agregar underscore)
└── _production_light.scss       ← NUEVO: reemplaza _production_dark.scss
```

**Orden de imports en `application.bootstrap.scss`:**
bootstrap → bootstrap-icons → variables → mixins → animations → navbar → notifications → devise_sessions → components → searchable_select → status_system → deliveries → delivery_plans → dashboard → production → production_light

**Archivos eliminados tras migración:**
`delivery.css`, `delivery_cards.css`, `delivery_detail.css`, `delivery_plans.css`,
`components.css`, `workspace.css`, `searchable_select.css`, `status_system.css`,
`notifications.css`, `dashboard.css`, `dashboard.css.backup`, `_production_dark.scss`

---

## 3. Variables globales (`_variables.scss`)

CSS custom properties en `:root`. Cambiar el bloque Brand propaga la nueva paleta a toda la app.

```scss
:root {
  // ── Brand ─────────────────────────────────────────────
  --color-brand-primary:    #0d6efd;
  --color-brand-accent:     #6610f2;
  --color-brand-bg:         #fff7ee;   // crema nalakalu

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

---

## 4. Tema claro del módulo Production (`_production_light.scss`)

Mismas clases que el tema oscuro (`pd-header`, `pd-card`, `pd-item-row`, `pd-btn-*`, `pd-bottom-sheet`, `pd-chip`). Solo cambian las variables del wrapper y los colores de cada clase.

El atributo en las vistas: `class="production-dark"` → `class="production-light"`.

**Paleta:**

```
Fondo página:      #f8f9fa
Fondo card:        #ffffff
Borde:             #dee2e6
Acento:            #0d6efd
Header gradient:   linear-gradient(135deg, #0d6efd, #6610f2)

Cargado:           texto #198754 · badge bg #d1e7dd · ítem bg #f0fdf4
Faltante:          texto #dc3545 · badge bg #f8d7da · ítem bg #fff5f5
Parcial/warning:   texto #856404 · badge bg #fff3cd · ítem bg #fffbeb
Sin estado:        texto #495057 · bg #f8f9fa

Nota/observación:  texto #664d03 · chip bg #fff3cd
```

**Diferencias visuales clave respecto al tema oscuro anterior:**

| Elemento | Oscuro (anterior) | Claro (nuevo) |
|---|---|---|
| Fondo página | `#0f0f1a` | `#f8f9fa` |
| Cards | `#1a1a2e` | `#ffffff` |
| Texto principal | `#f1f5f9` | `#212529` |
| Header | gradiente púrpura oscuro | gradiente azul-púrpura Bootstrap |
| Ítem cargado bg | `#051c0a` | `#f0fdf4` |
| Ítem faltante bg | `#1c0505` | `#fff5f5` |

**Conservado del spec anterior:**
- Botones táctiles mínimo 44px
- Bottom sheet de notas (overlay + panel deslizante)
- Cards colapsables por cliente
- Barra de búsqueda + chips de filtro
- Barra de progreso por plan
- Stats row de 4 celdas
- Todos los IDs Turbo Stream (`delivery_item_<id>`, `delivery_<id>`, `plan_header`, `load_summary`)

---

## 5. Consolidación de archivos CSS

| Archivo origen | Destino | Acción |
|---|---|---|
| `delivery.css` | `_deliveries.scss` | Renombrar + convertir a SCSS |
| `delivery_cards.css` | `_deliveries.scss` | Fusionar |
| `delivery_detail.css` | `_deliveries.scss` | Fusionar |
| `delivery_plans.css` | `_delivery_plans.scss` | Fusionar con el .scss existente |
| `delivery_plans.scss` | `_delivery_plans.scss` | Renombrar (agregar `_`) |
| `components.css` | `_components.scss` | Renombrar + convertir |
| `workspace.css` | `_components.scss` | Fusionar (utilidades genéricas) |
| `searchable_select.css` | `_searchable_select.scss` | Renombrar |
| `status_system.css` | `_status_system.scss` | Renombrar |
| `notifications.css` | `_notifications.scss` | Fusionar con partial existente |
| `production.scss` — flash/toast | `_production.scss` | Agregar `_`; conservar `.flash-*`, `.toast-notification` |
| `production.scss` — genéricos | `_components.scss` | Mover `.card:hover`, `.progress-bar`, `.btn.disabled` |
| `_production_dark.scss` | `_production_light.scss` | Reemplazar contenido completo |
| `dashboard.css` | `_dashboard.scss` | Fusionar al partial existente |
| `dashboard.css.backup` | — | Eliminar |

---

## 6. Extracción de inline styles

### Reglas

- **Solo estilos estáticos.** `style=` con interpolación Ruby (ej. `style="width: <%= pct %>%"`) permanecen inline.
- **Mailers excluidos** (`app/views/*_mailer/`): Gmail/Outlook requieren inline styles.
- Los estilos extraídos van al archivo SCSS del dominio más cercano.

### Vistas prioritarias (≥ 16 ocurrencias)

| Vista | Inline styles | Destino SCSS |
|---|---|---|
| `deliveries/show_partials/_summary_cards.html.erb` | 31 | `_deliveries.scss` |
| `driver/delivery_plans/index.html.erb` | 26 | `_delivery_plans.scss` |
| `production/delivery_plans/index.html.erb` | 24 | `_production_light.scss` |
| `deliveries/index_partials/_delivery_card_content.html.erb` | 22 | `_deliveries.scss` |
| `delivery_plans/edit_partials/_stops.html.erb` | 16 | `_delivery_plans.scss` |

### Vistas secundarias (< 16 ocurrencias)

Se limpian en la misma pasada:

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

### Destino por tipo de estilo

| Tipo | Destino |
|---|---|
| Colores de estado, badges semánticos | `_status_system.scss` |
| Layout de card, grids, paddings fijos | archivo del módulo correspondiente |
| Utilidades genéricas (sombras, bordes, transiciones) | `_components.scss` |
| Módulo production | `_production_light.scss` |

---

## 7. Manejo de errores y casos límite

- Si un inline `style=` mezcla valores estáticos y dinámicos, se divide: la parte estática va a una clase CSS, la dinámica permanece inline con solo ese atributo.
- Si dos archivos `.css` fusionados tienen clases con el mismo nombre y comportamiento diferente, se resuelve antes de fusionar (rename + grep para confirmar uso real).
- El orden de imports en `application.bootstrap.scss` sigue el orden de dependencia: variables siempre primero, componentes antes que módulos.

---

## 8. Scope explícito

**Dentro del alcance:**
- `app/assets/stylesheets/**` — toda la capa CSS
- `app/views/production/**` — cambiar `production-dark` → `production-light`
- Vistas no-mailer con inline `style=` estáticos

**Fuera del alcance:**
- `app/views/*_mailer/**` — inline styles de email se conservan
- `style=` con interpolación Ruby dinámica
- JS controllers, modelos, controllers Ruby, rutas
- Paleta de empresa (trabajo futuro)
