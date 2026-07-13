class Admin::VendorsController < ApplicationController
  before_action :set_vendor, only: [:edit, :update, :destroy]

  def index
    authorize Vendor
    @vendors = Vendor.includes(:vendor_contacts, :vendor_addresses).order(:name)
  end

  def new
    @vendor = Vendor.new
    @vendor.vendor_contacts.build
    @vendor.vendor_addresses.build
    authorize @vendor
  end

  def create
    @vendor = Vendor.new(vendor_params)
    authorize @vendor
    if @vendor.save
      redirect_to admin_vendors_path, notice: "Proveedor '#{@vendor.name}' creado correctamente."
    else
      @vendor.vendor_contacts.build if @vendor.vendor_contacts.empty?
      @vendor.vendor_addresses.build if @vendor.vendor_addresses.empty?
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @vendor.vendor_contacts.build
    @vendor.vendor_addresses.build
    authorize @vendor
  end

  def update
    @vendor.assign_attributes(vendor_params)
    authorize @vendor
    if @vendor.save
      redirect_to admin_vendors_path, notice: "Proveedor '#{@vendor.name}' actualizado correctamente."
    else
      @vendor.vendor_contacts.build
      @vendor.vendor_addresses.build
      render :edit, status: :unprocessable_entity
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
