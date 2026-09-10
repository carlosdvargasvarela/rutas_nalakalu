# Módulo: Policies (Pundit — autorización)

25 policies bajo `app/policies/`, todas heredan de `ApplicationPolicy` (fail-closed por defecto: `index?/show?/create?/update?/destroy?` devuelven `false` salvo que la policy concreta los sobreescriba). `ApplicationController` fuerza `after_action :verify_authorized` — toda acción que no llame `authorize`/`policy_scope` explota, salvo Devise/`public_*`/health/pwa.

Roles del enum `User#role`: `admin, production_manager, seller, logistics, driver, manager, proveeduria`.

## Puntos de mejora encontrados y corregidos

Todos con el mismo origen: **código copy-pasteado entre policies sin adaptar la asociación/columna al modelo real**. Se verificó cada uno ejecutando la query real contra la base (no solo lectura de código) — varios explotaban en runtime.

1. **🔴 Typo `"logistic"` vs `"logistics"` — bloqueaba el rol logistics en 3 policies**. `user.role.to_s == "logistic"` (singular) nunca matchea contra el valor real del enum (`"logistics"`, plural). Afectaba:
   - `DeliveryPlanPolicy` → `create?/update?/destroy?/send_to_logistics?/update_order?/add_delivery_to_plan?/mark_all_loaded?` denegados a logistics, y su `Scope` los mandaba al branch de "chofer" (`where(driver_id: user.id)`) mostrándoles 0 planes.
   - `DeliveryImportPolicy` → mismos verbos denegados a logistics.
   - `DeliveryPlanAssignmentPolicy#destroy?` → denegado a logistics.

   Reemplazado por `user.production_manager? || user.logistics?` (los helpers de enum que Rails ya genera) en los tres archivos.

2. **🔴 `DeliveryAddressPolicy#show?` explotaba para drivers**: `record.delivery_plan&.driver_id` — `DeliveryAddress` no tiene método `delivery_plan` (ni asociación alguna más allá de `belongs_to :client`). Confirmado con `NoMethodError: undefined method 'delivery_plan'`. Reescrito para consultar `Delivery.where(delivery_address_id: record.id).joins(delivery_plan_assignment: :delivery_plan).where(delivery_plans: {driver_id: user.id})`.

3. **`DeliveryAddressPolicy::Scope`, `OrderPolicy::Scope`, `UserPolicy::Scope`**: copiaban el join `joins(order: :seller)` / `joins(delivery_plan_assignments: {delivery_plan: :driver})` de `DeliveryPolicy::Scope` (correcto ahí, porque `Delivery belongs_to :order` y tiene `delivery_plan_assignment`) pero sin adaptar a un modelo que no tiene esas asociaciones. Confirmado con `ActiveRecord::ConfigurationError` para cada uno:
   - `OrderPolicy::Scope` → corregido a `joins(:seller)` (seller) y `joins(deliveries: {delivery_plan_assignment: :delivery_plan})` (driver, + `.distinct`).
   - `DeliveryAddressPolicy::Scope` → corregido a `joins(client: {orders: :seller})` (seller) y subquery sobre `Delivery` por `delivery_address_id` (driver).
   - `UserPolicy::Scope` → no tenía sentido semántico para el modelo User (nunca se usa: `Admin::UsersController` no llama `policy_scope`, `index?` ya restringe a admin/manager). Simplificado a `admin? || manager? ? scope.all : scope.none`.

   `DeliveryPolicy::Scope` (el original, correcto) tenía un bug propio: `delivery_plan_assignments` en plural, pero `Delivery` tiene `has_one :delivery_plan_assignment` (singular) → corregido el nombre de la asociación.

4. **`DeliveryImportPolicy::Scope`**: el branch "no privilegiado" hacía `scope.where(driver_id: user.id)`, pero la tabla `delivery_imports` no tiene columna `driver_id` (tiene `user_id`, el que subió el import) — habría lanzado `ActiveRecord::StatementInvalid` para cualquier seller/driver/manager. Corregido a `where(user_id: user.id)` (cada quien ve solo lo que subió).

Todas las policies con `Scope` afectadas estaban **sin uso real hoy** (ningún controller llama `policy_scope` sobre esos modelos todavía — verificado con grep), salvo el bug de `DeliveryAddressPolicy#show?`, que sí es una ruta viva (`GET /delivery_addresses/:id.json`, usada por los mapas) y estaba rota en producción para cualquier usuario driver. Los demás son bugs latentes que iban a explotar en cuanto alguien conectara `policy_scope` — igual se corrigieron porque son incorrectos independientemente de si hoy se ejecutan.

## Tests agregados

`test/policies/policy_regressions_test.rb` (7 tests) — cubre específicamente los 7 casos de arriba, para que estos bugs no puedan reintroducirse silenciosamente. Los tests existentes en `test/policies/*_test.rb` (delivery, order, tracking) son stubs vacíos heredados (`def test_show; end`) que no verifican nada — se dejaron así por no ser parte del alcance de esta pasada, pero quedan como gap de cobertura conocido.

**Suite completa: 260 tests, 0 fallos** (253 previos + 7 nuevos).
