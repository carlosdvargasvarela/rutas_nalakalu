# app/controllers/api/v1/deliveries_controller.rb
module Api
  module V1
    class DeliveriesController < ApplicationController
      # Saltar autenticación de usuario (Devise u otra)
      skip_before_action :authenticate_user!, raise: false

      # Saltar verificación de Pundit que sí existe
      skip_after_action :verify_authorized, raise: false
      # (Sólo agrega este si realmente tienes verify_policy_scoped en ApplicationController)
      # skip_after_action :verify_policy_scoped, raise: false

      protect_from_forgery with: :null_session

      # Cuando actives token entre apps:
      # before_action :authenticate_api_token!

      def index
        deliveries = base_scope.includes(
          :delivery_address,
          order: [:client, :seller],
          delivery_items: {order_item: :order}
        )

        render json: deliveries.map { |delivery| serialize_delivery(delivery) }
      end

      def show
        delivery = base_scope
          .includes(:delivery_address, order: %i[client seller], delivery_items: {order_item: :order})
          .find(params[:id])

        render json: serialize_delivery(delivery)
      rescue ActiveRecord::RecordNotFound
        render json: {error: "Delivery no encontrado"}, status: :not_found
      end

      private

      def base_scope
        scope = Delivery.all

        if params[:from].present?
          scope = scope.where("delivery_date >= ?", Date.parse(params[:from]))
        end

        if params[:to].present?
          scope = scope.where("delivery_date <= ?", Date.parse(params[:to]))
        end

        if params[:status].present?
          scope = scope.where(status: Delivery.statuses[params[:status]])
        end

        scope
      end

      def serialize_delivery(delivery)
        {
          id: delivery.id,
          delivery_date: delivery.delivery_date,
          order_number: delivery.order.number,
          status: delivery.status,
          status_label: delivery.display_status,
          seller_code: delivery.order.seller&.seller_code,
          client: {
            name: delivery.order.client.name
          },
          address: {
            address: delivery.delivery_address&.address,
            description: delivery.delivery_address&.description,
            latitude: delivery.latitude,
            longitude: delivery.longitude,
            plus_code: delivery.delivery_address&.plus_code
          },
          items: delivery.delivery_items.map { |item| serialize_item(item) }
        }
      end

      def serialize_item(item)
        {
          id: item.id,
          product_name: item.order_item.product,
          quantity_delivered: item.quantity_delivered,
          status: item.status,
          status_label: item.display_status,
          service_case: item.service_case,
          order_item_id: item.order_item_id
        }
      end

      # def authenticate_api_token!
      #   token = request.headers["X-Api-Token"]
      #   expected = Rails.application.credentials.dig(:api, :logistics_token) || ENV["LOGISTICS_API_TOKEN"]
      #
      #   unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected.to_s)
      #     render json: { error: "No autorizado" }, status: :unauthorized
      #   end
      # end
    end
  end
end
