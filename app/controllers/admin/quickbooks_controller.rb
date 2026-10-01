class Admin::QuickbooksController < ApplicationController
  def show
    @setting = AppSetting.find_or_initialize_by(key: "qb_sync_from_date")
    authorize @setting
    @standby_orders = Order.where(qb_standby: true).includes(:client).order(created_at: :desc)
    @standby = QbStandbyOrder.order(created_at: :desc)
  end

  def edit_standby
    authorize AppSetting.new(key: "qb_sync_from_date"), :update?
    @order = Order.find_by!(id: params[:id], qb_standby: true)
    @delivery = @order.deliveries.first
    @sellers = Seller.order(:name)
  end

  # Corrige dirección y productos de un pedido en stand-by (sigue sin ser operativo).
  def update_standby
    authorize AppSetting.new(key: "qb_sync_from_date"), :update?
    order = Order.find_by!(id: params[:id], qb_standby: true)
    delivery = order.deliveries.first
    Order.transaction do
      old_client = order.client
      client_name = params[:client_name].to_s.strip
      order.client = Client.find_or_create_by!(name: client_name) if client_name.present?
      order.seller = Seller.find(params[:seller_id]) if params[:seller_id].present?
      order.save!
      if params[:delivery_date].present?
        delivery.update_columns(delivery_date: Date.parse(params[:delivery_date]))
      end
      # la dirección pertenece al cliente: si cambia el cliente o el texto, se re-asocia
      address_text = params[:address].to_s.strip.presence || delivery.delivery_address.address
      if order.client != old_client || address_text != delivery.delivery_address.address
        delivery.update_columns(delivery_address_id: order.client.delivery_addresses.find_or_create_by!(address: address_text).id)
      end
      (params[:items] || {}).each do |id, attrs|
        item = order.order_items.find(id)
        if attrs[:remove] == "1"
          item.destroy!
        else
          qty = attrs[:quantity].to_i
          item.update!(product: attrs[:product].to_s.strip, quantity: qty)
          delivery.delivery_items.where(order_item: item).update_all(quantity_delivered: qty)
        end
      end
      if params[:new_product].to_s.strip.present?
        qty = params[:new_quantity].to_i.clamp(1, 100_000)
        item = order.order_items.create!(product: params[:new_product].strip, quantity: qty, status: :in_production)
        delivery.delivery_items.create!(order_item: item, quantity_delivered: qty, status: :pending)
      end
    end
    redirect_to admin_quickbooks_path, notice: "#{order.number} actualizado (sigue en stand-by)."
  rescue ActiveRecord::RecordInvalid, Date::Error => e
    redirect_to admin_edit_standby_quickbooks_path(params[:id]), alert: e.message
  end

  def release
    authorize AppSetting.new(key: "qb_sync_from_date"), :update?
    order = Order.find_by!(id: params[:id], qb_standby: true)
    if order.order_items.none?
      return redirect_to admin_quickbooks_path, alert: "#{order.number} no tiene productos: complételo antes de liberarlo."
    end
    placeholders = []
    placeholders << "cliente" if order.client.name == ProcessQuickbooksXmlJob::PLACEHOLDER_CLIENT
    placeholders << "vendedor" if order.seller.seller_code == ProcessQuickbooksXmlJob::PLACEHOLDER_SELLER_CODE
    placeholders << "dirección" if order.deliveries.first.delivery_address.address == ProcessQuickbooksXmlJob::PLACEHOLDER_ADDRESS
    if placeholders.any?
      return redirect_to admin_quickbooks_path, alert: "#{order.number}: falta definir #{placeholders.to_sentence} antes de liberarlo."
    end
    number = params[:number].to_s.strip.presence || order.number
    if Order.exists?(number: number, qb_standby: false)
      return redirect_to admin_quickbooks_path, alert: "#{number} ya existe: indique otro número para liberarlo."
    end
    Order.transaction do
      order.update_columns(number: number, qb_standby: false, qb_standby_reason: nil)
      order.deliveries.pending_review.update_all(status: Delivery.statuses[:scheduled])
    end
    redirect_to admin_quickbooks_path, notice: "#{number} liberado."
  end

  def update
    @setting = AppSetting.find_or_initialize_by(key: "qb_sync_from_date")
    authorize @setting

    date_str = params[:from_date].presence
    if date_str.blank?
      redirect_to admin_quickbooks_path, alert: "Debe ingresar una fecha."
      return
    end

    AppSetting.set("qb_sync_from_date", Date.parse(date_str).strftime("%Y-%m-%dT00:00:00"))
    redirect_to admin_quickbooks_path, notice: "Fecha de sincronización actualizada."
  rescue Date::Error
    redirect_to admin_quickbooks_path, alert: "Fecha inválida."
  end
end
