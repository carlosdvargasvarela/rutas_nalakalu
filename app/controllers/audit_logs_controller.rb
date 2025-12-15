# app/controllers/audit_logs_controller.rb
class AuditLogsController < ApplicationController
  helper :audit_logs
  before_action :authenticate_user!
  before_action :authorize_audit_access # Solo admin/producción

  def index
    @q = PaperTrail::Version.ransack(params[:q])
    @q.sorts = "created_at desc" if @q.sorts.empty?

    @versions = @q.result
      .page(params[:page])
      .per(50)

    user_ids = @versions.pluck(:whodunnit).compact.uniq
    @users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }

    @items_cache = preload_items(@versions)

    @item_types = PaperTrail::Version.distinct.pluck(:item_type).compact.sort
    @events = PaperTrail::Version.distinct.pluck(:event).compact

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def resource_history
    @item_type = params[:item_type]
    @item_id = params[:item_id]

    # 🔹 Scope base sin paginación para estadísticas
    base_scope = PaperTrail::Version.where(item_type: @item_type, item_id: @item_id)

    # 🔹 Calcular estadísticas sin ORDER BY ni paginación
    @events_count = base_scope.group(:event).count

    # 🔹 Versiones paginadas y ordenadas para el timeline
    @versions = base_scope
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @resource = @item_type.constantize.find_by(id: @item_id)

    user_ids = @versions.pluck(:whodunnit).compact.uniq
    @users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }

    @items_cache = preload_items(@versions)
  end

  def compare
    @version_from = PaperTrail::Version.find(params[:from_id])
    @version_to = PaperTrail::Version.find(params[:to_id])

    @diff = calculate_diff(@version_from, @version_to)
  end

  private

  def authorize_audit_access
    unless current_user.admin? || current_user.production?
      redirect_to root_path, alert: "No tienes permisos para ver el log de auditoría"
    end
  end

  def calculate_diff(version_from, version_to)
    obj_from = version_from.reify || {}
    obj_to = version_to.reify || {}

    all_keys = (obj_from.attributes.keys + obj_to.attributes.keys).uniq

    all_keys.each_with_object({}) do |key, diff|
      val_from = obj_from.try(:[], key)
      val_to = obj_to.try(:[], key)
      diff[key] = {from: val_from, to: val_to} if val_from != val_to
    end
  end

  def preload_items(versions)
    items_cache = {}
    versions_by_type = versions.group_by(&:item_type)

    versions_by_type.each do |type, type_versions|
      ids = type_versions.map(&:item_id).uniq.compact
      items_cache[type] = type.constantize.where(id: ids).index_by(&:id)
    rescue NameError => e
      Rails.logger.warn "No se pudo cargar el modelo #{type}: #{e.message}"
      items_cache[type] = {}
    rescue => e
      Rails.logger.error "Error al precargar items de #{type}: #{e.message}"
      items_cache[type] = {}
    end

    items_cache
  end
end
