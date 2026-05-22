# Revamp: Módulo Production / Delivery Plans

**Fecha:** 2026-05-22  
**Alcance:** Solo vistas y JS controllers dentro de `app/views/production/` y sus controllers Stimulus asociados.

---

## 1. Contexto y objetivo

El módulo `production/delivery_plans` es usado por el equipo de despacho para registrar la carga de camiones la noche/madrugada anterior al día de entrega. El flujo es: entrar al módulo → seleccionar un plan → marcar ítem por ítem como cargado, faltante o agregar notas.

**Problema actual:** La UI usa el tema claro estándar del sistema, con botones pequeños (`btn-sm`) poco aptos para uso táctil en bodega, y un diálogo `confirm()` nativo del browser para marcar faltantes que interrumpe el flujo.

**Objetivo:** Revamp completo de look & feel del módulo de producción con foco en mobile, manteniendo toda la lógica de backend y rutas existentes.

---

## 2. Decisiones de diseño

| Decisión | Elección | Razón |
|---|---|---|
| Tema visual | Vibrante Táctil (oscuro) | Bodega con poca luz, alto contraste, botones grandes |
| Paleta base | `#0f0f1a` fondo, `#7c3aed` acento | Legible en pantallas brillantes, energético |
| Estructura lista | Cards colapsables por cliente | Agrupa por parada, reduce scroll, estado visible |
| Notas | Bottom sheet por producto | Más espacio para escribir que inline, menos ruido |
| Confirmar faltante | Sin `confirm()`, con `↺ Desmarcar` | Patrón undo es más fluido en mobile |

---

## 3. Paleta de colores

```
Fondo principal:    #0f0f1a
Fondo card:         #1a1a2e
Fondo card inner:   #16213e / #12122a
Borde/divider:      #2d2d4e

Acento primario:    #7c3aed (púrpura)
Header gradient:    linear-gradient(135deg, #6d28d9, #4338ca)

Cargado (success):  texto #4ade80, fondo badge #166534, bg ítem #051c0a
Faltante (danger):  texto #f87171, fondo badge #7f1d1d, bg ítem #1c0505
Parcial (warning):  texto #fbbf24, fondo badge #78350f
Sin estado:         texto #94a3b8, fondo #1e1e38

Nota/observación:   texto #fde68a (amarillo)
```

---

## 4. Archivos a modificar

### Vistas Rails
| Archivo | Cambio |
|---|---|
| `app/views/production/delivery_plans/index.html.erb` | Rediseño completo con tema oscuro |
| `app/views/production/delivery_plans/loading.html.erb` | Rediseño con sticky header nuevo |
| `app/views/production/delivery_plans/_plan_header.html.erb` | Nuevo header con barra de progreso y stats row de 4 columnas |
| `app/views/production/delivery_plans/_load_summary.html.erb` | Rediseñado pero manteniendo su estructura como partial separado (ver nota Turbo Streams) |
| `app/views/production/deliveries/_delivery_card.html.erb` | Card colapsable rediseñada |
| `app/views/production/delivery_items/_delivery_item_row.html.erb` | Botones grandes, preview de nota |

### JS Stimulus
| Archivo | Cambio |
|---|---|
| `app/javascript/controllers/delivery_item_controller.js` | Agregar acción `openNoteSheet` / `saveNote`; quitar `confirm()` de `markMissing` |

### Backend (mínimo necesario para notas)
| Archivo | Cambio |
|---|---|
| `config/routes.rb` | Agregar `patch :add_note` a `production/delivery_items` member routes |
| `app/controllers/production/delivery_items_controller.rb` | Agregar acción `add_note` que actualiza `@delivery_item.notes` y responde con Turbo Stream |
| `app/policies/production/delivery_item_policy.rb` (o equivalente) | Agregar `add_note?` |

### CSS nuevo
| Archivo | Descripción |
|---|---|
| `app/assets/stylesheets/production.css` (nuevo) | Variables y clases de tema oscuro, bottom sheet, animaciones |

**No se toca:** layout, navbar, helpers fuera de `production/`, modelos, lógica de negocio.

---

## 5. Diseño de pantallas

### 5.1 Índice de planes (`index.html.erb`)

**Header** (gradiente púrpura):
- Título "🚛 Bitácora de Carga" + fecha actual
- Navegación de fecha: `‹` fecha `›` + botón "Hoy"

**Stats del día** (4 celdas):
- Total planes / Completos / En progreso / Con faltantes

**Cards de planes** (una por plan, orden: camión, driver):
- Franja de 3px en el tope con color semántico (verde/amarillo/rojo/gris)
- Avatar iniciales del chofer + nombre + badges (camión, plan#)
- Badge de estado (top-right)
- Barra de progreso con porcentaje
- Mini-stats: entregas / cargados / faltantes
- Botón CTA que cambia según estado:
  - Pendiente: "📋 Abrir Bitácora" (gradiente púrpura)
  - En progreso: "📋 Abrir Bitácora" (gradiente púrpura)
  - Completo: "✓ Ver bitácora completa" (verde)
  - Con faltantes: "⚠ Revisar faltantes" (rojo)

### Restricción crítica: Turbo Stream IDs

El controller `Production::DeliveryItemsController#render_item_update_streams` ya reemplaza via Turbo Stream los siguientes IDs del DOM:

- `delivery_item_<id>` — fila del ítem
- `delivery_<id>` — card de la entrega completa
- `plan_header` — header del plan
- `load_summary` — resumen de carga

Estos IDs **deben mantenerse** en las vistas rediseñadas. Los partials `_plan_header` y `_load_summary` son elementos separados aunque visualmente contiguos. El wrapper `id="plan_header"` en `loading.html.erb` y el wrapper `id="load_summary"` no se eliminan.

---

### 5.2 Bitácora de carga (`loading.html.erb`)

**Header sticky** (gradiente púrpura, z-index 100):
- Fila superior: `‹` atrás + avatar iniciales + nombre chofer + camión/plan/semana + badge de estado
- Barra de progreso del plan completo con porcentaje
- Stats row: Total / Cargados / Pendientes / Faltantes (4 celdas)

**Barra de búsqueda + filtros** (debajo del header):
- Input de búsqueda con ícono
- Chips horizontales scrolleables: Todos / Sin cargar / Parcial / Cargado ✓ / Faltantes ⚠
- Chip activo en `#7c3aed`, inactivos con borde y color semántico

**Lista de cards por cliente** (una por `DeliveryPlanAssignment`):
- Franja de 3px en el tope con color del estado de carga de esa entrega
- Header del card: número de parada (badge cuadrado) + nombre cliente + dirección + mini-progreso + chevron
- Al tocar el header: toggle colapsar/expandir los ítems
- Cards de entregas completadas aparecen colapsadas por defecto

**Filas de ítems** (dentro de cada card expandido):
- Fondo semántico: `#051c0a` si cargado, `#1c0505` si faltante, `#1a1a2e` si pendiente
- Nombre del producto (bold) + cantidad
- Si tiene nota: preview en amarillo con ícono 📝
- Badge de estado (top-right): "✓ OK" / "✗ Falta" / sin badge si pendiente
- Botones de acción (altura mínima 44px para touch):
  - Estado pendiente: `[✓ Cargado]` (verde) + `[✗ Faltante]` (rojo outline) + `[📝]` (gris)
  - Estado cargado: `[↺ Desmarcar]` + `[📝]` (verde outline)
  - Estado faltante: `[✓ Cargado]` + `[↺ Desmarcar]` + `[📝]` (amarillo outline)

**Footer de cada card** (visible solo cuando el card está expandido):
- `[✓✓ Marcar todo cargado]` + `[↺ Reset]`

### 5.3 Bottom Sheet de notas

Disparado por el botón 📝 en cualquier ítem. Implementado en CSS + JS puro (no Bootstrap modal):

- Overlay oscuro (`rgba(0,0,0,0.65)`) sobre el contenido
- Panel desde el fondo: `border-radius: 24px 24px 0 0`, `background: #1e1e38`
- Handle pill arriba
- Título "📝 Agregar nota" + botón ✕
- Contexto en chip: nombre producto + cantidad + cliente
- Textarea con texto en `#fde68a`
- Botones: `[Cancelar]` (gris) + `[💾 Guardar nota]` (gradiente ámbar)
- Al guardar: `fetch PATCH /production/delivery_items/:id/add_note` con el texto; el servidor responde con Turbo Stream que reemplaza `delivery_item_<id>` para mostrar el preview de la nota

---

## 6. Comportamiento JS (delivery_item_controller.js)

### Cambios al controller existente

**`markMissing()`** — eliminar el `confirm()`. La acción es instantánea. El botón `↺ Desmarcar` ya sirve como undo.

**Nuevo: `openNoteSheet(event)`**
- Lee `itemId`, `deliveryId`, nombre del producto y nota existente desde `data-*` del elemento
- Inyecta o actualiza el bottom sheet en el DOM (un solo sheet reutilizable en el body)
- Foca el textarea
- Cierra con el botón ✕ o click en el overlay

**Nuevo: `saveNote(event)`**
- `fetch PATCH` al endpoint existente de notas (o crear si no existe)
- Al éxito: cierra el sheet, actualiza el preview inline del ítem sin recarga

**Actualización de badges y fondos tras acción** — el controller ya lo maneja con `updateBadge()`. Se extiende para actualizar la clase de fondo del `item-row` (`item-row-loaded` / `item-row-missing`).

---

## 7. CSS nuevo (`production.css`)

Variables del tema oscuro scoped a `.production-dark`:

```css
.production-dark {
  --pd-bg: #0f0f1a;
  --pd-card: #1a1a2e;
  --pd-border: #2d2d4e;
  --pd-accent: #7c3aed;
  --pd-success: #4ade80;
  --pd-danger: #f87171;
  --pd-warning: #fbbf24;
  --pd-text: #f1f5f9;
  --pd-muted: #64748b;
}
```

Clases principales: `.pd-header`, `.pd-card`, `.pd-item-row`, `.pd-btn-ok`, `.pd-btn-miss`, `.pd-btn-note`, `.pd-bottom-sheet`, `.pd-chip`.

Animación de entrada del bottom sheet: `transform: translateY(100%)` → `translateY(0)` con `transition: 0.25s ease-out`.

---

## 8. Manejo de errores

- Error de red en `markLoaded/markMissing`: mostrar badge rojo "Error" y restaurar el estado anterior (comportamiento ya existente en `showErrorState()`).
- Error al guardar nota: mantener el bottom sheet abierto con un mensaje inline "No se pudo guardar. Intenta de nuevo."
- Sin conexión: el `offline_queue_controller.js` existente ya maneja la cola offline — no se modifica.

---

## 9. Scope explícito

**Dentro del alcance:**
- `app/views/production/**`
- `app/javascript/controllers/delivery_item_controller.js`
- `app/assets/stylesheets/production.css` (nuevo archivo)
- `config/routes.rb` — solo agregar `patch :add_note` en production/delivery_items
- `app/controllers/production/delivery_items_controller.rb` — solo agregar acción `add_note`
- Policy de `DeliveryItem` — solo agregar `add_note?`

**Fuera del alcance:**
- Layout (`application.html.erb`)
- Navbar / sidebar
- Cualquier vista fuera de `production/`
- Modelos, controllers Ruby, rutas
- Otros módulos del sistema
