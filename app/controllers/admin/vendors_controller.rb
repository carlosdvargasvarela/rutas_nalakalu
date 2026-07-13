class Admin::VendorsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_vendor, only: [:edit, :update, :destroy]

  def index
    authorize Vendor
    @vendors = Vendor.includes(:vendor_contacts, :vendor_addresses).order(:name)
  end

  def new
    @vendor = Vendor.new
    @vendor.vendor_contacts.build
    authorize @vendor
  end

  def create
    @vendor = Vendor.new(vendor_params)
    authorize @vendor
    if @vendor.save
      redirect_to admin_vendors_path, notice: "Proveedor '#{@vendor.name}' creado correctamente."
    else
      @vendor.vendor_contacts.build if @vendor.vendor_contacts.empty?
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @vendor.vendor_contacts.build
    authorize @vendor
    render layout: false if turbo_frame_request?
  end

  def update
    @vendor.assign_attributes(vendor_params)
    authorize @vendor
    if @vendor.save
      respond_to do |format|
        format.html { redirect_to admin_vendors_path, notice: "Proveedor '#{@vendor.name}' actualizado correctamente." }
        format.turbo_stream do
          flash.now[:notice] = "Proveedor '#{@vendor.name}' actualizado correctamente."
          render turbo_stream: [
            turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
            turbo_stream.replace("vendor_detail", partial: "admin/vendors/detail", locals: {vendor: @vendor}),
            turbo_stream.replace(dom_id(@vendor, :card), partial: "admin/vendors/vendor_card", locals: {vendor: @vendor})
          ]
        end
      end
    else
      @vendor.vendor_contacts.build
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("vendor_detail", partial: "admin/vendors/detail", locals: {vendor: @vendor}),
                 status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    authorize @vendor
    @vendor.destroy
    redirect_to admin_vendors_path, notice: "Proveedor eliminado."
  end

  private

  def set_vendor
    @vendor = Vendor.find(params[:id])
  end

  def vendor_params
    params.require(:vendor).permit(
      :name,
      vendor_contacts_attributes: [:id, :name, :phone, :is_primary, :_destroy],
      vendor_addresses_attributes: [:id, :address, :description, :latitude, :longitude, :plus_code, :_destroy]
    )
  end
end
