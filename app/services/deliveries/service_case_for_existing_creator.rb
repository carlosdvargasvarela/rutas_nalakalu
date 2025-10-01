# app/services/deliveries/service_case_for_existing_creator.rb
module Deliveries
  class ServiceCaseForExistingCreator
    def initialize(parent_delivery:, params:, current_user:)
      @parent_delivery = parent_delivery
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        @service_case = Delivery.new(service_case_params.merge(
          order: parent_delivery.order,
          delivery_address: parent_delivery.delivery_address,
          contact_name: params[:delivery][:contact_name] || parent_delivery.contact_name,
          contact_phone: params[:delivery][:contact_phone] || parent_delivery.contact_phone,
          status: :scheduled
        ))

        if params[:delivery][:delivery_items_attributes].present?
          @service_case.delivery_items = process_service_items(parent_delivery.order)
        elsif params[:copy_items] == "1"
          copy_items_from_parent
        end

        @service_case.save!
      end

      @service_case
    rescue => e
      Rails.logger.error("❌ Error en Deliveries::ServiceCaseForExistingCreator: #{e.message}")
      raise e
    end

    private

    attr_reader :parent_delivery, :params, :current_user, :service_case

    def service_case_params
      params.require(:delivery).permit(
        :delivery_date,
        :delivery_type,
        :delivery_notes,
        :delivery_time_preference
      )
    end

    def process_service_items(order)
      params[:delivery][:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"

        order_item = if item_params[:order_item_id].present?
          OrderItem.find(item_params[:order_item_id])
        else
          order.order_items.find_or_create_by!(
            product: item_params.dig(:order_item_attributes, :product)
          )
        end

        DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: item_params[:quantity_delivered].presence || 1,
          notes: item_params[:notes],
          service_case: true,
          status: :pending
        )
      end.compact
    end

    def copy_items_from_parent
      parent_delivery.delivery_items.map do |item|
        @service_case.delivery_items.build(
          order_item: item.order_item,
          quantity_delivered: item.quantity_delivered,
          service_case: true,
          status: :pending
        )
      end
    end
  end
end