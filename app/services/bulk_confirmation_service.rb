# app/services/bulk_confirmation_service.rb
class BulkConfirmationService
  def initialize(order_items)
    @order_items = order_items
  end

  def confirm_all!
    @order_items.each(&:confirm!)
  end
end