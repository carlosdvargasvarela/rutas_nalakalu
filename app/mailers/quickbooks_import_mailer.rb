class QuickbooksImportMailer < ApplicationMailer
  default from: "NaLakalu Notificaciones <alerts@nalakalu.com>"

  def seller_orders_loaded
    @seller = params[:seller]
    @orders_data = Array.wrap(params[:orders_data]).map(&:with_indifferent_access)
    @created_count = @orders_data.count { |o| o[:action] == "created" }
    @updated_count = @orders_data.count { |o| o[:action] == "updated" }

    mail(
      to: @seller.user.email,
      subject: "📦 #{@orders_data.size == 1 ? "Pedido cargado" : "#{@orders_data.size} pedidos cargados"} desde QuickBooks – #{Date.today.strftime("%d/%m/%Y")}"
    )
  end

  def admin_orders_loaded
    @admin = params[:admin]
    raw = params[:results_by_seller] || {}
    @sellers_data = raw.map do |seller_code, orders|
      {
        seller: Seller.find_by(seller_code: seller_code),
        seller_code: seller_code,
        orders: Array.wrap(orders).map(&:with_indifferent_access)
      }
    end
    @all_orders = @sellers_data.flat_map { |d| d[:orders] }
    @created_count = @all_orders.count { |o| o[:action] == "created" }
    @updated_count = @all_orders.count { |o| o[:action] == "updated" }

    mail(
      to: @admin.email,
      subject: "📊 QuickBooks: #{@all_orders.size} pedido#{@all_orders.size == 1 ? "" : "s"} procesado#{@all_orders.size == 1 ? "" : "s"} – #{Date.today.strftime("%d/%m/%Y")}"
    )
  end

  def admin_orders_rejected
    @admin = params[:admin]
    @rejected = Array.wrap(params[:rejected]).map(&:with_indifferent_access)

    mail(
      to: @admin.email,
      subject: "⚠️ QuickBooks: #{@rejected.size} pedido#{@rejected.size == 1 ? "" : "s"} rechazado#{@rejected.size == 1 ? "" : "s"} – #{Date.today.strftime("%d/%m/%Y")}"
    )
  end
end
