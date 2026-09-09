class Admin::VendorsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_vendor, only: [:edit, :update, :destroy]

  def index
    authorize Vendor
    @vendors = Vendor.includes(:vendor_contacts, :vendor_addresses).order(:name)
  end

  def new
    @vendor = Vendor.new
    ensure_business_hours!(@vendor)
    authorize @vendor
  end

  def create
    @vendor = Vendor.new(vendor_params)
    authorize @vendor
    if @vendor.save
      respond_to do |format|
        format.html { redirect_to admin_vendors_path, notice: "Proveedor '#{@vendor.name}' creado correctamente." }
        format.turbo_stream { render turbo_stream: close_modal_and_refresh_vendor_select }
      end
    else
      ensure_business_hours!(@vendor)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    ensure_business_hours!(@vendor)
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
          if from_modal?
            render turbo_stream: close_modal_and_refresh_vendor_select
          else
            flash.now[:notice] = "Proveedor '#{@vendor.name}' actualizado correctamente."
            render turbo_stream: [
              turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
              turbo_stream.replace("vendor_detail", partial: "admin/vendors/detail", locals: {vendor: @vendor}),
              turbo_stream.replace(dom_id(@vendor, :card), partial: "admin/vendors/vendor_card", locals: {vendor: @vendor})
            ]
          end
        end
      end
    else
      ensure_business_hours!(@vendor)
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream do
          stream = if from_modal?
            turbo_stream.replace("modal", partial: "admin/vendors/modal_form", locals: {vendor: @vendor})
          else
            turbo_stream.replace("vendor_detail", partial: "admin/vendors/detail", locals: {vendor: @vendor})
          end
          render turbo_stream: stream, status: :unprocessable_entity
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

  def from_modal?
    turbo_frame_request_id == "modal"
  end

  def close_modal_and_refresh_vendor_select
    [
      turbo_stream.update("modal", ""),
      turbo_stream.update("vendor_address_select_container",
        partial: "deliveries/internal_delivery_partials/vendor_address_select")
    ]
  end

  def vendor_params
    params.require(:vendor).permit(
      :name,
      vendor_addresses_attributes: [:id, :address, :description, :latitude, :longitude, :plus_code, :_destroy],
      vendor_business_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :closed]
    )
  end

  # El formulario siempre muestra los 7 días; completa los que aún no existen
  # en BD con registros nuevos (sin guardar) para que el usuario los llene.
  def ensure_business_hours!(vendor)
    existing_days = vendor.vendor_business_hours.map(&:day_of_week)
    (0..6).each do |day|
      next if existing_days.include?(day)
      vendor.vendor_business_hours.build(day_of_week: day, closed: true)
    end
  end
end
