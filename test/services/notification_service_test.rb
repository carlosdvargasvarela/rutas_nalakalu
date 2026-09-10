require "test_helper"
require "minitest/mock"

class NotificationServiceTest < ActiveSupport::TestCase
  # RESCHEDULE_NOTIFICATION_EMAILS se lee del ENV una sola vez al cargar la
  # clase, así que para poder testear el flujo "hay destinatarios externos"
  # hace falta swappear la constante en el setup/teardown.
  setup do
    @original_emails = NotificationService::RESCHEDULE_NOTIFICATION_EMAILS
    NotificationService.send(:remove_const, :RESCHEDULE_NOTIFICATION_EMAILS)
    NotificationService.const_set(:RESCHEDULE_NOTIFICATION_EMAILS, ["logistica@nalakalu.com"])
  end

  teardown do
    NotificationService.send(:remove_const, :RESCHEDULE_NOTIFICATION_EMAILS)
    NotificationService.const_set(:RESCHEDULE_NOTIFICATION_EMAILS, @original_emails)
  end

  # Regresión: notify_delivery_rescheduled enviaba correo externo incluso
  # para mandados internos, a diferencia del resto de notificaciones de
  # reagendamiento del servicio (notify_current_week_delivery_rescheduled,
  # notify_bulk_items_rescheduled), que ya excluían internal_delivery.
  test "notify_delivery_rescheduled does not email externally for internal deliveries" do
    delivery = deliveries(:one)
    delivery.update!(delivery_type: :internal_delivery)

    NotificationMailer.stub :safe_notify_external, ->(**) { raise "should not be called for internal deliveries" } do
      NotificationService.notify_delivery_rescheduled(delivery, old_date: 1.day.ago.to_date, rescheduled_by: "Tester")
    end

    assert true # no exception raised above means safe_notify_external was never called
  end

  test "notify_delivery_rescheduled emails externally for normal deliveries" do
    delivery = deliveries(:one)
    delivery.update!(delivery_type: :normal)

    called = false
    NotificationMailer.stub :safe_notify_external, ->(**) { called = true } do
      NotificationService.notify_delivery_rescheduled(delivery, old_date: 1.day.ago.to_date, rescheduled_by: "Tester")
    end

    assert called, "expected safe_notify_external to be called for a normal delivery"
  end
end
