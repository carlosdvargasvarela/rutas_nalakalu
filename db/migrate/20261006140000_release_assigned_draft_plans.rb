class ReleaseAssignedDraftPlans < ActiveRecord::Migration[7.2]
  # Planes que quedaron en borrador con conductor o camión no le aparecían al conductor.
  def up
    execute "UPDATE delivery_plans SET status = 2 WHERE status = 0 AND (driver_id IS NOT NULL OR truck IS NOT NULL)"
  end

  def down
  end
end
