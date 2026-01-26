# app/jobs/seller_delivery_summary_job.rb
class SellerDeliverySummaryJob
  include Sidekiq::Job

  sidekiq_options queue: "mailers", retry: 3

  def perform
    Rails.logger.info "🚀 [SellerDeliverySummaryJob] Iniciando envío de resúmenes de entregas cargadas..."

    service = Deliveries::GenerateSellerSummary.new
    summaries = service.call

    if summaries.empty?
      Rails.logger.info "✅ [SellerDeliverySummaryJob] No hay entregas nuevas para notificar"
      return
    end

    # 1. Enviar a cada vendedor
    summaries.each do |seller_id, data|
      seller = Seller.find_by(id: seller_id)
      next unless seller&.user&.email

      begin
        SellerDeliverySummaryMailer.with(
          seller: seller,
          deliveries: data[:deliveries],
          summary: data[:summary]
        ).delivery_summary.deliver_later

        Rails.logger.info "📧 [SellerDeliverySummaryJob] Correo enviado a #{seller.user.email} (#{data[:deliveries].count} entregas)"
      rescue => e
        Rails.logger.error "❌ [SellerDeliverySummaryJob] Error enviando a #{seller.user.email}: #{e.message}"
      end
    end

    # 2. Enviar resumen consolidado a admins
    send_consolidated_summary_to_admins(summaries)

    Rails.logger.info "✅ [SellerDeliverySummaryJob] Completado. #{summaries.count} vendedores notificados"
  end

  private

  def send_consolidated_summary_to_admins(summaries)
    admin_users = User.where(role: :admin).where.not(email: nil)

    if admin_users.empty?
      Rails.logger.warn "⚠️ [SellerDeliverySummaryJob] No hay admins con email configurado"
      return
    end

    # Calcular estadísticas globales
    all_deliveries = summaries.values.flat_map { |data| data[:deliveries] }
    global_summary = {
      total_sellers: summaries.count,
      total_deliveries: all_deliveries.count,
      total_items: all_deliveries.sum { |d| d.delivery_items.count },
      total_with_errors: all_deliveries.count { |d| has_delivery_errors?(d) },
      by_seller: summaries.transform_values { |data| data[:summary] }
    }

    admin_users.each do |admin|
      SellerDeliverySummaryMailer.with(
        admin: admin,
        summaries: summaries,
        global_summary: global_summary
      ).consolidated_admin_summary.deliver_later

      Rails.logger.info "📧 [SellerDeliverySummaryJob] Resumen consolidado enviado a admin #{admin.email}"
    rescue => e
      Rails.logger.error "❌ [SellerDeliverySummaryJob] Error enviando a admin #{admin.email}: #{e.message}"
    end
  end

  def has_delivery_errors?(delivery)
    Deliveries::ErrorDetector.new(delivery).has_errors?
  end
end
