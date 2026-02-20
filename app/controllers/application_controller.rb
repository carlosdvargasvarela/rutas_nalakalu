# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  layout :set_layout

  before_action :set_paper_trail_whodunnit
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_password_change

  after_action :verify_authorized, unless: :skip_authorization?

  def pundit_user
    current_user
  end

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # 🔹 NUEVO: Redirigir según rol después del login
  def after_sign_in_path_for(resource)
    if resource.force_password_change?
      edit_user_registration_path
    elsif resource.production_manager?
      management_production_deliveries_path  # 👈 Vista de producción
    elsif resource.driver?
      driver_delivery_plans_path             # 👈 Vista de chofer
    elsif resource.logistics?
      delivery_plans_path                    # 👈 Vista de logística
    else
      root_path                              # 👈 Dashboard genérico (vendedores, admin)
    end
  end

  private

  def user_not_authorized
    flash[:alert] = "No tienes permiso para realizar esta acción."
    redirect_to(request.referrer || root_path)
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name, :role])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name, :role])
  end

  def check_password_change
    return unless current_user&.force_password_change?

    unless devise_controller? && action_name.in?(%w[edit update destroy])
      redirect_to edit_user_registration_path, alert: "Debes cambiar tu contraseña antes de continuar."
    end
  end

  def set_layout
    if controller_path.start_with?("driver/")
      "driver"
    elsif controller_path.start_with?("public_")
      "public"
    else
      "application"
    end
  end

  def skip_authorization?
    devise_controller? ||
      controller_path.start_with?("public_") ||
      controller_name == "rails/health" ||
      controller_name == "pwa"
  end
end
