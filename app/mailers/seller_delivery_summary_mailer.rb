# app/mailers/seller_delivery_summary_mailer.rb
class SellerDeliverySummaryMailer < ApplicationMailer
  default from: "reportes@nalakalu.com"

  # Correo individual para vendedores
  def delivery_summary
    @seller = params[:seller]
    @deliveries = params[:deliveries]
    @summary = params[:summary]
    @recipient = @seller.user.email

    # Agrupar entregas por fecha
    @deliveries_by_date = @deliveries.group_by { |d| d.delivery_date }.sort

    mail(
      to: @recipient,
      subject: "📦 Resumen de entregas cargadas – #{Date.today.strftime("%d de %B de %Y")}"
    )
  end

  # Correo consolidado para admins
  def consolidated_admin_summary
    @admin = params[:admin]
    @summaries = params[:summaries]
    @global_summary = params[:global_summary]

    # Agrupar todas las entregas por fecha
    all_deliveries = @summaries.values.flat_map { |data| data[:deliveries] }
    @deliveries_by_date = all_deliveries.group_by { |d| d.delivery_date }.sort

    mail(
      to: @admin.email,
      subject: "📊 Resumen Consolidado de Entregas – #{Date.today.strftime("%d de %B de %Y")}"
    )
  end
end
