# app/controllers/admin/users_controller.rb
class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_user, only: [ :edit, :update, :send_reset_password, :unlock, :toggle_notifications ]

  def index
    @users = User.order(:name)
  end

  def new
    @user = User.new
    # Si quieres preconstruir un miembro cuando el rol se seleccione por JS, lo hacemos en la vista con Stimulus.
  end

  def create
    @user = User.new(user_params.except(:seller_code))
    @user.seller_code = user_params[:seller_code]
    @user.password = "Nalakalu.01"

    User.transaction do
      if @user.save!
        if @user.seller? && user_params[:seller_code].present?
          Seller.create!(user: @user, name: @user.name, seller_code: user_params[:seller_code])
        end
        @user.send_reset_password_instructions
      end
    end

    redirect_to admin_users_path, notice: "Usuario creado y correo enviado para establecer contraseña."
  rescue ActiveRecord::RecordInvalid => e
    render :new, status: :unprocessable_entity
  end

  def edit
    # UX: si es driver y no tiene crew, construir una fila vacía
    @user.crew_members.build if @user.driver? && @user.crew_members.empty?
  end

  def update
    attrs = user_params
    # No forzar cambio de contraseña si vienen en blanco
    if attrs[:password].blank? && attrs[:password_confirmation].blank?
      attrs = attrs.except(:password, :password_confirmation)
    end

    if @user.update(attrs)
      if @user.seller? && @user.seller.blank? && user_params[:seller_code].present?
        Seller.find_or_create_by!(user: @user) do |s|
          s.name = @user.name
          s.seller_code = user_params[:seller_code]
        end
      end
      redirect_to admin_users_path, notice: "Usuario actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
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
    new_status = !@user.send_notifications
    @user.update_column(:send_notifications, new_status)
    status = new_status ? "activadas" : "desactivadas"
    redirect_to admin_users_path, notice: "Notificaciones #{status} para #{@user.name}"
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  # Permitir crew_members_attributes
  def user_params
    params.require(:user).permit(
      :name, :email, :role, :seller_code, :send_notifications,
      :password, :password_confirmation, # por si editas credenciales
      crew_members_attributes: [ :id, :name, :id_number, :_destroy ]
    )
  end

  def require_admin!
    redirect_to root_path, alert: "No autorizado" unless current_user.admin?
  end
end