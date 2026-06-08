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

      MAX_PER_PAGE = 200
      DEFAULT_PER_PAGE = 50

      # Cuando actives token entre apps:
      # before_action :authenticate_api_token!

      def index
        deliveries = base_scope
          .includes(
            :delivery_address,
            :source_showroom,
            :destination_showroom,
            order: [:client, :seller],
            delivery_items: {order_item: :order}
          )
          .order(updated_at: :asc, id: :asc)

        # La paginación es opcional (vía ?page=) para no romper a los
        # consumidores existentes que esperan el arreglo completo en la raíz.
        if params[:page].present?
          deliveries = deliveries.page(params[:page]).per(per_page)
          set_pagination_headers(deliveries)
        end

        render json: deliveries.map { |delivery| serialize_delivery(delivery) }
      end

      def show
        delivery = base_scope
          .includes(
            :delivery_address,
            :source_showroom,
            :destination_showroom,
            order: %i[client seller],
            delivery_items: {order_item: :order}
          )
          .find(params[:id])

        render json: serialize_delivery(delivery)
      rescue ActiveRecord::RecordNotFound
        render json: {error: "Delivery no encontrado"}, status: :not_found
      end

      private

      def per_page
        return DEFAULT_PER_PAGE if params[:per_page].blank?

        params[:per_page].to_i.clamp(1, MAX_PER_PAGE)
      end

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

        if params[:delivery_type].present?
          scope = scope.where(delivery_type: Delivery.delivery_types[params[:delivery_type]])
        end

        # Sincronización incremental: sólo entregas modificadas desde cierto momento
        if params[:updated_since].present?
          scope = scope.where("deliveries.updated_at >= ?", Time.zone.parse(params[:updated_since]))
        end

        if params[:archived].present?
          scope = scope.where(archived: ActiveModel::Type::Boolean.new.cast(params[:archived]))
        end

        scope
      end

      def set_pagination_headers(scope)
        response.set_header("X-Current-Page", scope.current_page.to_s)
        response.set_header("X-Total-Pages", scope.total_pages.to_s)
        response.set_header("X-Total-Count", scope.total_count.to_s)
        response.set_header("X-Per-Page", scope.limit_value.to_s)
      end

      def serialize_delivery(delivery)
        {
          id: delivery.id,
          tracking_token: delivery.tracking_token,
          delivery_date: delivery.delivery_date,
          delivery_time_preference: delivery.delivery_time_preference,
          status: delivery.status,
          status_label: delivery.display_status,
          delivery_type: delivery.delivery_type,
          delivery_type_label: delivery.display_type,
          load_status: delivery.load_status,
          load_status_label: delivery.display_load_status,
          approved: delivery.approved,
          archived: delivery.archived,
          confirmed_by_vendor: delivery.confirmed_by_vendor,
          confirmed_by_vendor_at: delivery.confirmed_by_vendor_at,
          reschedule_reason: delivery.reschedule_reason,
          warehousing_until: delivery.warehousing_until,
          order_number: delivery.order.number,
          seller_code: delivery.order.seller&.seller_code,
          condominio_number: delivery.condominio_number,
          casa_number: delivery.casa_number,
          source_showroom: serialize_showroom(delivery.source_showroom),
          destination_showroom: serialize_showroom(delivery.destination_showroom),
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
          items: delivery.delivery_items.map { |item| serialize_item(item) },
          updated_at: delivery.updated_at,
          created_at: delivery.created_at
        }
      end

      def serialize_showroom(showroom)
        return nil if showroom.blank?

        {
          id: showroom.id,
          name: showroom.name,
          code: showroom.code
        }
      end

      def serialize_item(item)
        {
          id: item.id,
          order_item_id: item.order_item_id,
          product_name: item.order_item.product,
          quantity_delivered: item.quantity_delivered,
          loaded_quantity: item.loaded_quantity,
          status: item.status,
          status_label: item.display_status,
          load_status: item.load_status,
          load_status_label: item.display_load_status,
          service_case: item.service_case,
          sala_pickup_requested: item.sala_pickup_requested,
          notes: item.notes
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
