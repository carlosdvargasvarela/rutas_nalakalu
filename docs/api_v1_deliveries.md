# API de Entregas (Api::V1::Deliveries)

API de solo lectura para que aplicaciones externas (p. ej. el sistema de inventario)
consuman información de entregas (deliveries) generada por Rutas Nalakalu.

Base path: `/api/v1/deliveries`

> Autenticación: actualmente la API no requiere autenticación (`authenticate_user!`
> está deshabilitado para este namespace). Hay un mecanismo de token preparado pero
> comentado en el controlador (`authenticate_api_token!`) por si se activa más adelante.

---

## Endpoints

### `GET /api/v1/deliveries`

Devuelve un arreglo JSON con las entregas que cumplen los filtros indicados.

**Por compatibilidad, la respuesta es siempre un arreglo JSON en la raíz** —
no un objeto envoltorio — sin importar si se usa paginación o no.

#### Parámetros de filtro (todos opcionales, combinables)

| Parámetro | Tipo | Descripción |
|---|---|---|
| `from` | fecha (`YYYY-MM-DD`) | Sólo entregas con `delivery_date >= from` |
| `to` | fecha (`YYYY-MM-DD`) | Sólo entregas con `delivery_date <= to` |
| `status` | string | Filtra por estado de la entrega (ver [Valores de `status`](#valores-de-status)) |
| `delivery_type` | string | Filtra por tipo de entrega (ver [Valores de `delivery_type`](#valores-de-delivery_type)) |
| `archived` | booleano (`true`/`false`) | Si se omite, se incluyen tanto archivadas como no archivadas (igual que antes). Si se envía, filtra exactamente por ese valor de `archived` |
| `updated_since` | fecha/hora ISO-8601 (p. ej. `2026-06-01T00:00:00Z`) | Sincronización incremental: sólo entregas cuyo `updated_at >= updated_since`. Útil para que el consumidor sólo traiga lo que cambió desde su última sincronización |

Ejemplo:

```
GET /api/v1/deliveries?from=2026-06-01&to=2026-06-30&status=ready_to_deliver&updated_since=2026-06-07T00:00:00Z
```

#### Paginación (opcional)

La paginación es **opt-in**: si no se envía `page`, la respuesta trae **todas**
las entregas que cumplen los filtros (igual que el comportamiento histórico de
esta API). Si se envía `page`, la respuesta trae sólo esa página, y la
información de paginación viaja en **encabezados HTTP** (no cambia la forma del
JSON, que sigue siendo un arreglo en la raíz):

| Parámetro | Default | Máximo | Descripción |
|---|---|---|---|
| `page` | — | — | Número de página (1-based). Si está presente, activa la paginación |
| `per_page` | `50` | `200` | Cantidad de entregas por página |

Encabezados de respuesta cuando se pagina:

| Header | Descripción |
|---|---|
| `X-Current-Page` | Página actual |
| `X-Total-Pages` | Total de páginas disponibles |
| `X-Total-Count` | Total de entregas que cumplen los filtros |
| `X-Per-Page` | Tamaño de página efectivo |

Las entregas siempre se devuelven ordenadas por `updated_at ASC, id ASC`, lo
cual hace que la combinación `updated_since` + `page` sea estable y apta para
sincronización incremental robusta (no se "saltan" ni duplican registros entre
páginas mientras no haya nuevas modificaciones).

Ejemplo de sincronización incremental recomendada:

```
GET /api/v1/deliveries?updated_since=<última_marca_de_tiempo_guardada>&page=1&per_page=100
```

El consumidor guarda el `updated_at` más reciente recibido como su nueva marca
de tiempo para la siguiente sincronización.

---

### `GET /api/v1/deliveries/:id`

Devuelve el JSON de una sola entrega (mismo formato que cada elemento del
arreglo de `index`).

Respuestas:

- `200 OK` con el objeto de la entrega
- `404 Not Found` con `{ "error": "Delivery no encontrado" }` si el `id` no existe

---

## Forma del objeto "Delivery"

```jsonc
{
  "id": 123,
  "tracking_token": "ab12...xyz",          // token único para el seguimiento público
  "delivery_date": "2026-06-10",
  "delivery_time_preference": "Tarde",
  "status": "ready_to_deliver",            // valor crudo del enum (ver tabla)
  "status_label": "Confirmada para entregar", // etiqueta legible en español
  "delivery_type": "normal",               // valor crudo del enum (ver tabla)
  "delivery_type_label": "Entrega normal", // etiqueta legible en español
  "load_status": "partial",                // estado de carga en camión (ver tabla)
  "load_status_label": "Parcialmente cargado",
  "approved": true,
  "archived": false,
  "confirmed_by_vendor": true,
  "confirmed_by_vendor_at": "2026-06-08T10:00:00.000-06:00",
  "reschedule_reason": null,
  "warehousing_until": null,               // fecha límite de bodegaje, si aplica
  "order_number": "12345",
  "seller_code": "VEN01",
  "condominio_number": null,
  "casa_number": "12B",
  "source_showroom": {                     // null si no aplica
    "id": 1,
    "name": "Sala Escazú",
    "code": "ESC"
  },
  "destination_showroom": null,            // null si no aplica
  "client": {
    "name": "Juan Pérez"
  },
  "address": {
    "address": "San José, Costa Rica...",
    "description": "Casa color blanco, portón negro",
    "latitude": 9.928,
    "longitude": -84.090,
    "plus_code": "76MR+2X San José"
  },
  "items": [ /* ver "Forma del objeto item" */ ],
  "updated_at": "2026-06-08T10:00:00.000-06:00",
  "created_at": "2026-06-01T08:00:00.000-06:00"
}
```

### Forma del objeto "item" (dentro de `items`)

```jsonc
{
  "id": 456,
  "order_item_id": 789,
  "product_name": "Sofá 3 puestos modelo X",
  "quantity_delivered": 1,
  "loaded_quantity": 1,                  // cantidad cargada en camión (puede ser null)
  "status": "confirmed",                 // valor crudo del enum (ver tabla)
  "status_label": "Confirmado",
  "load_status": "loaded",               // estado de carga del ítem (ver tabla)
  "load_status_label": "Cargado",
  "service_case": false,                 // true si es un caso de servicio
  "sala_pickup_requested": false,        // true si se solicitó retiro en sala
  "notes": null
}
```

---

## Catálogos de valores (enums)

### Valores de `status` (entrega)

| Valor crudo | Etiqueta (`status_label`) |
|---|---|
| `scheduled` | Pendiente de confirmar |
| `ready_to_deliver` | Confirmada para entregar |
| `in_plan` | En plan |
| `in_route` | En ruta |
| `delivered` | Entregada |
| `rescheduled` | Reprogramada |
| `cancelled` | Cancelada |
| `archived` | Archivada |
| `failed` | Entrega fracasada |
| `loaded_on_truck` | Cargada en camión |
| `warehousing` | En bodegaje |

### Valores de `delivery_type`

| Valor crudo | Etiqueta (`delivery_type_label`) |
|---|---|
| `normal` | Entrega normal |
| `pickup_with_return` | Retiro del producto en sala y entrega posterior al cliente |
| `return_delivery` | Devolución de producto |
| `onsite_repair` | Reparación en sitio |
| `only_pickup` | Solo retiro del producto (sin entrega posterior) |
| `internal_delivery` | Mandado Interno |
| `showroom` | Movimiento de Showroom |
| `repair_pickup` | Servicio de Reparación — Recolección |
| `repair_return` | Servicio de Reparación — Devolución |

### Valores de `load_status` (entrega e ítem)

| Valor crudo (entrega) | Etiqueta | Valor crudo (ítem) | Etiqueta |
|---|---|---|---|
| `empty` | Sin cargar | `unloaded` | Sin cargar |
| `partial` | Parcialmente cargado | `loaded` | Cargado |
| `all_loaded` | Completamente cargado | `missing` | Faltante |
| `some_missing` | Con faltantes | | |

> Nota: el enum de carga de la **entrega** y el del **ítem** tienen valores
> crudos distintos (la entrega resume el estado de carga de todos sus ítems).

### Valores de `status` (ítem de entrega)

| Valor crudo | Etiqueta (`status_label`) |
|---|---|
| `pending` | Pendiente de confirmar |
| `confirmed` | Confirmado |
| `in_plan` | En plan de entregas |
| `in_route` | En ruta |
| `delivered` | Entregado |
| `rescheduled` | Reprogramado |
| `cancelled` | Cancelado |
| `failed` | Entrega fracasada |
| `loaded_on_truck` | Cargado en camión |

---

## Notas de compatibilidad

- La raíz de `index` siempre es un **arreglo** de entregas — nunca un objeto
  envoltorio — para no romper integraciones existentes.
- Los nuevos campos son **aditivos**: cualquier consumidor que ignore claves
  desconocidas seguirá funcionando sin cambios.
- La paginación es **opcional**: si no se envía `page`, el comportamiento es
  idéntico al histórico (se devuelven todas las entregas que cumplan los
  filtros).
- El filtro `archived` es opcional y no cambia el conjunto de resultados por
  defecto: si no se envía, se incluyen tanto entregas archivadas como no
  archivadas, igual que antes.

## Recomendaciones de uso para integraciones

- Para sincronizar el catálogo de inventario de forma eficiente, usar
  `updated_since` + `page`/`per_page` en lugar de traer todo el listado en
  cada corrida.
- Guardar el `updated_at` más reciente devuelto como marca de tiempo para la
  siguiente sincronización.
- Tratar `status`, `delivery_type` y `load_status` como **valores estables**
  (no traducir por `*_label`, que es texto libre en español pensado para UI y
  puede cambiar de redacción).
