# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  layout :set_layout

  before_action :set_paper_trail_whodunnit
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_password_change

  # Manejo global de errores de autorización
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def after_sign_in_path_for(resource)
    if resource.force_password_change?
      edit_user_registration_path # formulario Devise de edición de perfil/contraseña
    else
      super
    end
  end

  private

  def user_not_authorized
    flash[:alert] = "No tienes permiso para realizar esta acción."
    redirect_to(request.referer || root_path)
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name, :role])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name, :role])
  end

  def check_password_change
    return unless current_user&.force_password_change?

    # Evita bucles infinitos / permitir acciones de cerrar sesión, actualizar perfil, etc.
    unless devise_controller? && action_name.in?(%w[edit update destroy])
      redirect_to edit_user_registration_path, alert: "Debes cambiar tu contraseña antes de continuar."
    end
  end

  def set_layout
    if controller_path.start_with?("driver/")
      "driver"
    else
      "application"
    end
  end
end
