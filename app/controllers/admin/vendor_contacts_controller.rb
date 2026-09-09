class Admin::VendorContactsController < ApplicationController
  before_action :set_vendor
  before_action :set_contact, only: [:update, :destroy]

  def create
    @contact = @vendor.vendor_contacts.build(contact_params)
    authorize @contact

    if @contact.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "vendor_contacts_#{@vendor.id}",
            partial: "admin/vendors/contacts",
            locals: {vendor: @vendor}
          )
        end
        format.html { redirect_to edit_admin_vendor_path(@vendor), notice: "Contacto agregado correctamente." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "vendor_contacts_#{@vendor.id}",
            partial: "admin/vendors/contacts",
            locals: {vendor: @vendor, errors: @contact.errors}
          ), status: :unprocessable_entity
        end
        format.html { redirect_to edit_admin_vendor_path(@vendor), alert: @contact.errors.full_messages.to_sentence }
      end
    end
  end

  def update
    authorize @contact

    if @contact.update(contact_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "vendor_contacts_#{@vendor.id}",
            partial: "admin/vendors/contacts",
            locals: {vendor: @vendor}
          )
        end
        format.html { redirect_to edit_admin_vendor_path(@vendor), notice: "Contacto actualizado correctamente." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "vendor_contacts_#{@vendor.id}",
            partial: "admin/vendors/contacts",
            locals: {vendor: @vendor, errors: @contact.errors}
          ), status: :unprocessable_entity
        end
        format.html { redirect_to edit_admin_vendor_path(@vendor), alert: @contact.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    authorize @contact
    @contact.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "vendor_contacts_#{@vendor.id}",
          partial: "admin/vendors/contacts",
          locals: {vendor: @vendor}
        )
      end
      format.html { redirect_to edit_admin_vendor_path(@vendor), notice: "Contacto eliminado correctamente." }
    end
  end

  private

  def set_vendor
    @vendor = Vendor.find(params[:vendor_id])
  end

  def set_contact
    @contact = @vendor.vendor_contacts.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to edit_admin_vendor_path(@vendor), alert: "Contacto no encontrado."
  end

  def contact_params
    params.require(:vendor_contact).permit(:name, :phone, :is_primary)
  end
end
