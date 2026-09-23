class Production::DeliveryItemsController < ApplicationController
  include LoadingStreams

  before_action :authenticate_user!
  include Pundit::Authorization

  before_action :set_delivery_item
  before_action :reject_if_load_closed, only: %i[mark_loaded mark_unloaded mark_missing]

  def mark_loaded
    authorize @delivery_item, :mark_loaded?
    @delivery_item.mark_loaded!
    respond_with_streams
  rescue StandardError => e
    flash.now[:alert] = e.message
    respond_with_streams
  end

  def mark_unloaded
    authorize @delivery_item, :mark_unloaded?
    @delivery_item.mark_unloaded!
    respond_with_streams
  end

  def mark_missing
    authorize @delivery_item, :mark_missing?
    @delivery_item.mark_missing!(reason: params[:reason], actor: current_user)
    respond_with_streams
  end

  def add_note
    authorize @delivery_item, :add_note?
    @delivery_item.update!(notes: params[:note].to_s.strip)
    respond_with_streams
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end

  def reject_if_load_closed
    return unless @delivery_item.delivery.delivery_plan&.load_closed?

    redirect_back fallback_location: root_path, alert: "La carga de este camión ya está cerrada."
  end

  def respond_with_streams
    delivery = @delivery_item.reload.delivery
    respond_to do |format|
      format.turbo_stream { render turbo_stream: loading_streams(delivery) }
      format.html { redirect_back fallback_location: root_path }
      format.json { render json: {success: true, item: @delivery_item} }
    end
  end
end
