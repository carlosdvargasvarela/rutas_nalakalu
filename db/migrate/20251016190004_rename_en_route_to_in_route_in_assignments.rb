# db/migrate/20250416000002_rename_en_route_to_in_route_in_assignments.rb
class RenameEnRouteToInRouteInAssignments < ActiveRecord::Migration[7.2]
  def up
    # Cambiar el valor del enum de 'en_route' (1) a 'in_route' (1)
    # Como usamos integer enums, no necesitamos cambiar datos, solo el código
    # Pero si alguien guardó strings, ejecutamos esto:
    execute <<-SQL
      UPDATE delivery_plan_assignments
      SET status = 1
      WHERE status = 1;
    SQL
  end

  def down
    # No-op, el enum sigue siendo el mismo valor numérico
  end
end
