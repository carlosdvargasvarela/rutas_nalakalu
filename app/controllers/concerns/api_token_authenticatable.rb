module ApiTokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_token!
  end

  private

  def authenticate_api_token!
    token = request.headers["X-Driver-Token"].presence
    @current_api_user = token && User.find_by(api_token: token)
    render json: { error: "No autorizado" }, status: :unauthorized unless @current_api_user
  end

  def current_user
    @current_api_user
  end
end
