# app/controllers/order_contacts_controller.rb
class OrderContactsController < ApplicationController
  before_action :set_order
  before_action :set_contact, only: [:update, :destroy]

  def index
    authorize @order, :show?
    contacts = @order.order_contacts.primary_first
    render json: contacts.map { |c| { id: c.id, name: c.name, phone: c.phone, is_primary: c.is_primary } }
  end

  def create
    @contact = @order.order_contacts.build(contact_params)
    authorize @contact

    if @contact.save
      respond_to do |format|
        format.json { render json: { id: @contact.id, name: @contact.name, phone: @contact.phone, is_primary: @contact.is_primary }, status: :created }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "order_contacts_#{@order.id}",
            partial: "orders/contacts",
            locals: { order: @order }
          )
        end
        format.html { redirect_to order_path(@order), notice: "Contacto agregado correctamente." }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @contact.errors.full_messages }, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "order_contacts_#{@order.id}",
            partial: "orders/contacts",
            locals: { order: @order, errors: @contact.errors }
          )
        end
        format.html { redirect_to order_path(@order), alert: @contact.errors.full_messages.to_sentence }
      end
    end
  end

  def update
    authorize @contact

    if @contact.update(contact_params)
      respond_to do |format|
        format.json { render json: { id: @contact.id, name: @contact.name, phone: @contact.phone, is_primary: @contact.is_primary } }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "order_contacts_#{@order.id}",
            partial: "orders/contacts",
            locals: { order: @order }
          )
        end
        format.html { redirect_to order_path(@order), notice: "Contacto actualizado correctamente." }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @contact.errors.full_messages }, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "order_contacts_#{@order.id}",
            partial: "orders/contacts",
            locals: { order: @order, errors: @contact.errors }
          )
        end
        format.html { redirect_to order_path(@order), alert: @contact.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    authorize @contact
    @contact.destroy

    respond_to do |format|
      format.json { head :no_content }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "order_contacts_#{@order.id}",
          partial: "orders/contacts",
          locals: { order: @order }
        )
      end
      format.html { redirect_to order_path(@order), notice: "Contacto eliminado correctamente." }
    end
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end

  def set_contact
    @contact = @order.order_contacts.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to order_path(@order), alert: "Contacto no encontrado."
  end

  def contact_params
    params.require(:order_contact).permit(:name, :phone, :is_primary)
  end
end
