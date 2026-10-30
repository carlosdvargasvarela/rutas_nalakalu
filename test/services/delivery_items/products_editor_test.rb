require "test_helper"

class DeliveryItems::ProductsEditorTest < ActiveSupport::TestCase
  setup do
    @admin = users(:one)
    @admin.update!(role: :admin)
    @delivery = deliveries(:one)
    @delivery.delivery_items.destroy_all
    @order = @delivery.order
    @order.order_items.destroy_all
    @sofa = add_item("Sofá", 2)
    @mesa = add_item("Mesa", 1)
  end

  def add_item(product, quantity, delivery: @delivery)
    order_item = @order.order_items.create!(product: product, quantity: quantity, status: :ready)
    delivery.delivery_items.create!(order_item: order_item, quantity_delivered: quantity, status: :pending)
  end

  def edit(items: {}, new_items: [], user: @admin)
    DeliveryItems::ProductsEditor.new(
      delivery: @delivery,
      items: items.with_indifferent_access,
      new_items: new_items.map(&:with_indifferent_access),
      current_user: user
    ).call
  end

  test "renombrar y cambiar cantidad corrige el producto del pedido y marca el pedido" do
    assert_difference -> { @delivery.delivery_events.where(action: "item_edited").count }, 1 do
      edit(items: {@sofa.id => {product: "Sofá gris", quantity: "3"}})
    end

    assert_equal "Sofá gris", @sofa.order_item.reload.product
    assert_equal 3, @sofa.order_item.quantity
    assert_equal 3, @sofa.reload.quantity_delivered
    assert @order.reload.products_edited_at.present?
  end

  test "sin cambios reales no marca el pedido" do
    assert_equal 0, edit(items: {@sofa.id => {product: "Sofá", quantity: "2"}})
    assert_nil @order.reload.products_edited_at
  end

  test "con el producto repartido en otra entrega el pedido solo cambia por la diferencia" do
    other = Delivery.create!(order: @order, delivery_address: @delivery.delivery_address, delivery_date: @delivery.delivery_date + 3.days, status: :scheduled)
    other.delivery_items.create!(order_item: @sofa.order_item, quantity_delivered: 3, status: :pending)
    @sofa.order_item.update!(quantity: 5)

    edit(items: {@sofa.id => {product: "Sofá", quantity: "1"}})

    assert_equal 4, @sofa.order_item.reload.quantity
  end

  test "agregar un producto lo crea en el pedido con el estado de la entrega" do
    @delivery.delivery_items.update_all(status: DeliveryItem.statuses[:confirmed])
    @delivery.update!(status: :ready_to_deliver)

    edit(new_items: [{product: "Lámpara", quantity: "2"}, {product: " ", quantity: "1"}])

    item = @delivery.delivery_items.joins(:order_item).find_by(order_items: {product: "Lámpara"})
    assert_equal "confirmed", item.status
    assert_equal 2, item.order_item.quantity
  end

  test "archivar el único registro cancela el producto y no frena al pedido; reagregarlo lo recupera" do
    @mesa.order_item.update!(status: :delivered)
    @sofa.update!(status: :delivered)

    edit(items: {@mesa.id => {archive: "1"}})

    assert_equal "cancelled", @mesa.order_item.reload.status
    assert_equal "delivered", @order.reload.status
    assert_equal 2, @order.total_items

    @delivery.update_column(:status, Delivery.statuses[:scheduled])
    edit(new_items: [{product: "Mesa", quantity: "2"}])

    assert_equal 1, @order.order_items.where(product: "Mesa").count
    assert_not @mesa.reload.archived?
    assert_equal 2, @mesa.quantity_delivered
    assert_equal 2, @mesa.order_item.reload.quantity
    assert_not_equal "cancelled", @mesa.order_item.status
  end

  test "archivar con el producto vigente en otra entrega resta solo esa parte" do
    other = Delivery.create!(order: @order, delivery_address: @delivery.delivery_address, delivery_date: @delivery.delivery_date + 3.days, status: :scheduled)
    other.delivery_items.create!(order_item: @sofa.order_item, quantity_delivered: 3, status: :pending)
    @sofa.order_item.update!(quantity: 5)

    edit(items: {@sofa.id => {archive: "1"}})

    assert_equal 3, @sofa.order_item.reload.quantity
    assert_not_equal "cancelled", @sofa.order_item.status
  end

  test "reemplazar un producto y dejar la entrega vacía o duplicar se revierte completo" do
    assert_raises(StandardError) { edit(items: {@sofa.id => {archive: "1"}, @mesa.id => {archive: "1"}}) }
    assert_not @sofa.reload.archived?

    assert_raises(StandardError) { edit(items: {@sofa.id => {product: "Otro", quantity: "2"}}, new_items: [{product: "Mesa", quantity: "1"}]) }
    assert_equal "Sofá", @sofa.order_item.reload.product

    assert_raises(StandardError) { edit(items: {@sofa.id => {product: "Sofá", quantity: "0"}}) }
  end

  test "dos filas con el mismo nombre dan un error que nombra el producto y no guardan nada" do
    error = assert_raises(StandardError) do
      edit(items: {@sofa.id => {product: "Repetido ", quantity: "2"}, @mesa.id => {product: "Repetido", quantity: "1"}})
    end

    assert_includes error.message, "«Repetido»"
    assert_equal "Sofá", @sofa.order_item.reload.product
  end

  test "un nombre con espacios sobrantes de QuickBooks no cuenta como cambio" do
    @sofa.order_item.update_column(:product, "Sofá ")

    assert_equal 0, edit(items: {@sofa.id => {product: "Sofá", quantity: "2"}})
    assert_equal "Sofá ", @sofa.order_item.reload.product
  end

  test "solo un admin archiva, y un producto entregado no se puede tocar" do
    @admin.update!(role: :logistics)
    assert_raises(StandardError) { edit(items: {@sofa.id => {archive: "1"}}) }
    assert_not @sofa.reload.archived?

    @sofa.update!(status: :delivered)
    assert_raises(ActiveRecord::RecordNotFound) { edit(items: {@sofa.id => {product: "X", quantity: "1"}}) }
  end
end
