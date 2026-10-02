# Pedidos de QuickBooks que no se pueden cargar sin riesgo (número ya usado por otra
# transacción, o error al procesar). Quedan retenidos aquí; nunca tocan un Order existente.
class QbStandbyOrder < ApplicationRecord
  serialize :payload, coder: JSON

  def self.hold(so, order_number, reason)
    rec = find_or_initialize_by(qb_txn_id: so["txn_id"].to_s)
    rec.update!(order_number: order_number.start_with?("PED-") ? order_number : "PED-#{order_number}", reason: reason.to_s.truncate(500), payload: so)
  end
end
