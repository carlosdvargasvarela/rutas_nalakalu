require "test_helper"

module Admin
  class DeliveriesVocabulariesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      ServiceTypeWord.delete_all
      DetectorKeywordList.delete_all
      @admin = users(:one)
      @admin.update!(role: :admin, force_password_change: false)
      sign_in @admin
    end

    test "admin can view the vocabulary form" do
      get admin_deliveries_vocabulary_path

      assert_response :success
      assert_includes @response.body, "Vocabulario de entregas"
    end

    test "a seller cannot view or update the vocabulary" do
      seller = users(:two)
      seller.update!(role: :seller, force_password_change: false)
      sign_in seller

      get admin_deliveries_vocabulary_path
      assert_response :redirect

      patch admin_deliveries_vocabulary_path, params: {service_types: {}, keyword_lists: {}}
      assert_response :redirect
    end

    test "update persists service type labels and detector keyword lists" do
      patch admin_deliveries_vocabulary_path, params: {
        service_types: full_service_types_params(recoleccion: {label: "Pickup", prefix: "Pickup - "}),
        keyword_lists: {
          service_case: {keywords: "frase uno, frase dos"}
        }
      }

      assert_redirected_to admin_deliveries_vocabulary_path

      word = ServiceTypeWord.find_by!(key: "recoleccion")
      assert_equal "Pickup", word.label
      assert_equal "Pickup - ", word.prefix

      list = DetectorKeywordList.find_by!(detector: "service_case", list_name: "keywords")
      assert_equal ["frase uno", "frase dos"], list.values_list
    end

    test "update changes take effect on a freshly built detector without restarting the app" do
      patch admin_deliveries_vocabulary_path, params: {
        service_types: full_service_types_params,
        keyword_lists: {
          repair_service: {keywords: "palabra_de_prueba_admin"}
        }
      }
      assert_response :redirect

      delivery = Delivery.new(status: "scheduled")
      delivery.delivery_items.build(
        order_item: OrderItem.new(product: "Mesa palabra_de_prueba_admin", quantity: 1),
        status: "pending",
        quantity_delivered: 1
      )

      assert Deliveries::RepairServiceDetector.new(delivery).requires_repair_service?
    end

    private

    # Mimics a real form submit: the view always renders every service type
    # field pre-filled with its current value, so a genuine PATCH never omits
    # a key. `overrides` lets a test customize a subset of them.
    def full_service_types_params(overrides = {})
      Deliveries::Vocabulary.service_types.each_with_object({}) do |(key, attrs), params|
        params[key] = overrides[key.to_sym] || {label: attrs["label"], prefix: attrs["prefix"]}
      end
    end
  end
end
