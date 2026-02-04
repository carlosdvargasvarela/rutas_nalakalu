# app/policies/public_tracking_policy.rb
class PublicTrackingPolicy < Struct.new(:user, :public_tracking)
  # El primer argumento es 'user', que será nil para visitantes anónimos.
  # El segundo es el registro (en este caso no lo usamos mucho, pero Pundit lo requiere).

  def show?
    true # Cualquiera con el token puede ver la página
  end
end
