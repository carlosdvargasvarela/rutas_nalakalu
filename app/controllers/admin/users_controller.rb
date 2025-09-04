# app/controllers/admin/users_controller.rb
class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_user, only: [ :send_reset_password, :unlock, :toggle_notifications ]

  def index
    @users = User.order(:name)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.except(:seller_code))
    @user.seller_code = user_params[:seller_code] # Asigna el campo virtual
    @user.password = "Nalakalu.01"

    User.transaction do
      if @user.save!
        if @user.seller? && user_params[:seller_code].present?
          seller = Seller.new(user: @user, name: @user.name, seller_code: user_params[:seller_code])
          seller.save
        end
        @user.send_reset_password_instructions
      end
    end

    redirect_to admin_users_path, notice: "Usuario creado y correo enviado para establecer contraseña."
  rescue ActiveRecord::RecordInvalid => e
    # Si algo falla, captura el error y renderiza el formulario con errores
    render :new, status: :unprocessable_entity
  end

  def send_reset_password
    @user.send_reset_password_instructions
    redirect_to admin_users_path, notice: "Correo de acceso reenviado a #{@user.email}"
  end

  def unlock
    @user.unlock_access! if @user.access_locked?
    redirect_to admin_users_path, notice: "Usuario desbloqueado"
  end

  def toggle_notifications
    @user.update!(send_notifications: !@user.send_notifications)
    status = @user.send_notifications? ? "activadas" : "desactivadas"
    redirect_to admin_users_path, notice: "Notificaciones #{status} para #{@user.name}"
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :role, :seller_code, :send_notifications)
  end

  def require_admin!
    redirect_to root_path, alert: "No autorizado" unless current_user.admin?
  end
end
