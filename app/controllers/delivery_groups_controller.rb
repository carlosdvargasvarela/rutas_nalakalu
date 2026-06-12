class DeliveryGroupsController < ApplicationController
  before_action :set_source, only: [:create]
  before_action :set_group,  only: [:remove_member]

  def create
    authorize DeliveryGroup

    target_number = params[:target_order_number].to_s.strip

    if target_number.blank?
      return render_link_error(@source, "Ingresá el número de pedido.")
    end

    target = Delivery.joins(:order).find_by(orders: { number: target_number })

    unless target
      return render_link_error(@source, "No se encontró ninguna entrega con el pedido \"#{target_number}\".")
    end

    if @source.id == target.id
      return render_link_error(@source, "No podés vincular un pedido consigo mismo.")
    end

    link_deliveries!(@source, target)

    render turbo_stream: turbo_stream.replace(
      "associated_deliveries_#{@source.id}",
      partial: "deliveries/associated_deliveries",
      locals: { delivery: @source.reload }
    )
  rescue => e
    render_link_error(@source, e.message)
  end

  def remove_member
    authorize @group
    current = Delivery.find(params[:current_delivery_id])
    target  = Delivery.find(params[:delivery_id])

    @group.deliveries.delete(target)
    @group.reload.destroy! if @group.deliveries.count <= 1

    render turbo_stream: turbo_stream.replace(
      "associated_deliveries_#{current.id}",
      partial: "deliveries/associated_deliveries",
      locals: { delivery: current.reload }
    )
  end

  private

  def set_source
    @source = Delivery.find(params[:source_delivery_id])
  end

  def set_group
    @group = DeliveryGroup.find(params[:id])
  end

  def link_deliveries!(source, target)
    source_group = source.reload.delivery_group
    target_group = target.reload.delivery_group

    if source_group && target_group
      return if source_group == target_group
      # Merge: move all of target_group's memberships into source_group
      target_group.delivery_group_memberships.update_all(delivery_group_id: source_group.id)
      target_group.reload.destroy!
    elsif source_group
      source_group.deliveries << target
    elsif target_group
      target_group.deliveries << source
    else
      group = DeliveryGroup.create!
      group.deliveries << source
      group.deliveries << target
    end
  end

  def render_link_error(delivery, message)
    render turbo_stream: turbo_stream.replace(
      "associated_deliveries_#{delivery.id}",
      partial: "deliveries/associated_deliveries",
      locals: { delivery: delivery, link_error: message }
    )
  end
end
