# app/jobs/seller_delivery_summary_job.rb
class SellerDeliverySummaryJob
  include Sidekiq::Job

  sidekiq_options queue: "mailers", retry: 3

  # solo_admins: si es true, no envía correos a vendedores, solo el consolidado a admins
  def perform(solo_admins = false)
    Rails.logger.info "🚀 [SellerDeliverySummaryJob] Iniciando envío de resúmenes de entregas cargadas..."

    service = Deliveries::GenerateSellerSummary.new
    summaries = service.call

    if summaries.empty?
      Rails.logger.info "✅ [SellerDeliverySummaryJob] No hay entregas nuevas para notificar"
      return
    end

    send_to_sellers(summaries) unless solo_admins
    send_consolidated_summary_to_admins(summaries)

    Rails.logger.info "✅ [SellerDeliverySummaryJob] Completado. #{summaries.count} vendedor(es) detectado(s) (solo_admins=#{solo_admins})"
  end

  private

  def send_to_sellers(summaries)
    summaries.each do |seller_id, data|
      seller = Seller.find_by(id: seller_id)
      next unless seller&.user&.email

      # ✅ Verificar que el usuario tenga notificaciones habilitadas
      unless seller.user.send_notifications?
        Rails.logger.info "⏭️  [SellerDeliverySummaryJob] Vendedor #{seller.user.email} tiene notificaciones deshabilitadas, omitiendo..."
        next
      end

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
  end

  def send_consolidated_summary_to_admins(summaries)
    # ✅ Filtrar admins con email Y con notificaciones habilitadas
    admin_users = User.where(role: :admin)
      .where(send_notifications: true)

    if admin_users.empty?
      Rails.logger.warn "⚠️ [SellerDeliverySummaryJob] No hay admins con email y notificaciones habilitadas"
      return
    end

    # ✅ Convertir claves Integer a String para que ActiveJob pueda serializar
    summaries_for_job = summaries.transform_keys(&:to_s)

    all_deliveries = summaries_for_job.values.flat_map { |data| data[:deliveries] }

    global_summary = {
      total_sellers: summaries_for_job.count,
      total_deliveries: all_deliveries.count,
      total_items: all_deliveries.sum { |d| d.delivery_items.count },
      total_with_errors: all_deliveries.count { |d| Deliveries::ErrorDetector.new(d).has_errors? },
      by_seller: summaries_for_job.transform_values { |data| data[:summary] }
    }

    admin_users.each do |admin|
      SellerDeliverySummaryMailer.with(
        admin: admin,
        summaries: summaries_for_job,     # ✅ claves string
        global_summary: global_summary
      ).consolidated_admin_summary.deliver_later

      Rails.logger.info "📧 [SellerDeliverySummaryJob] Resumen consolidado enviado a admin #{admin.email}"
    rescue => e
      Rails.logger.error "❌ [SellerDeliverySummaryJob] Error enviando a admin #{admin.email}: #{e.message}"
    end
  end
end
