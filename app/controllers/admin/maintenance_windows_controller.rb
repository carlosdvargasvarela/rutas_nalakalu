# app/controllers/admin/maintenance_windows_controller.rb
class Admin::MaintenanceWindowsController < ApplicationController
  def show
    @window = MaintenanceWindow.current_window
    @users = User.order(:name)
    authorize @window || MaintenanceWindow.new
  end

  def new
    @window = MaintenanceWindow.new
    @users = User.order(:name)
    authorize @window
  end

  def create
    @window = MaintenanceWindow.new
    authorize @window

    MaintenanceWindow.where(active: true).update_all(active: false)

    duration_minutes = params[:maintenance_window][:duration_minutes].to_i
    ends_at = (duration_minutes > 0) ? duration_minutes.minutes.from_now : nil

    allowed_ids = Array(params[:maintenance_window][:allowed_user_ids])
      .map(&:to_i).reject(&:zero?)
    allowed_ids << current_user.id
    allowed_ids.uniq!

    @window = MaintenanceWindow.new(
      active: true,
      activated_by: current_user,
      ends_at: ends_at,
      allowed_user_ids: allowed_ids,
      message: params[:maintenance_window][:message]
    )

    if @window.save
      redirect_to admin_maintenance_window_path,
        notice: "Modo mantenimiento activado correctamente."
    else
      @users = User.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def deactivate
    @window = MaintenanceWindow.current_window || MaintenanceWindow.new
    authorize @window

    MaintenanceWindow.where(active: true).update_all(active: false)
    redirect_to admin_maintenance_window_path,
      notice: "Sistema rehabilitado. Todos los usuarios pueden acceder."
  end
end
