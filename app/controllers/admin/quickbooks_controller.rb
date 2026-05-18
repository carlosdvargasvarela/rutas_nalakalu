class Admin::QuickbooksController < ApplicationController
  def show
    @setting = AppSetting.find_or_initialize_by(key: "qb_sync_from_date")
    authorize @setting
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
