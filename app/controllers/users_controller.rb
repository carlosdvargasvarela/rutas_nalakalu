# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def index
    @users = User.order(:name)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.password = Devise.friendly_token.first(12) # Contraseña aleatoria temporal
    if @user.save
      @user.send_reset_password_instructions # Envía email para establecer contraseña
      redirect_to users_path, notice: "Usuario creado y correo enviado para establecer contraseña."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def send_reset_password
    user = User.find(params[:id])
    user.send_reset_password_instructions
    redirect_to users_path, notice: "Correo de acceso reenviado a #{user.email}"
  end

  def unlock
    user = User.find(params[:id])
    user.unlock_access! if user.access_locked?
    redirect_to users_path, notice: "Usuario desbloqueado"
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :role)
  end

  def require_admin!
    redirect_to root_path, alert: "No autorizado" unless current_user.admin?
  end
end
