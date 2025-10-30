class AuditLogsController < ApplicationController
  include Pundit::Authorization
  before_action :authenticate_user!

  def index
    authorize :audit_log, :index?

    # Base: todas las versiones de PaperTrail
    versions = PaperTrail::Version.all

    # Ransack para filtros
    @q = versions.ransack(search_params)
    @q.sorts = "created_at desc" if @q.sorts.empty?
    @versions = @q.result

    # Paginación
    @versions = @versions.page(params[:page]).per(50)

    # Pre-resolución de usuarios por whodunnit (que guarda user_id típico)
    @users_by_id = User.where(id: @versions.map(&:whodunnit).compact.uniq).index_by { |u| u.id.to_s }

    # Listado de modelos comunes para el filtro
    @item_types = %w[Order Delivery DeliveryItem DeliveryPlan Client Seller User DeliveryPlanAssignment OrderItem OrderItemNote DeliveryAddress Notification]
    @events     = [ [ "Creado", "create" ], [ "Actualizado", "update" ], [ "Eliminado", "destroy" ] ]
  end

  private

  def search_params
    # Esperamos parámetros tipo Ransack
    params.fetch(:q, {}).permit(:item_type_eq, :whodunnit_eq, :event_eq, :created_at_gteq, :created_at_lteq)
  end
end
