class Admin::ShowroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_showroom, only: [:edit, :update, :destroy]

  def index
    authorize Showroom
    @showrooms = Showroom.includes(:delivery_address).order(:name)
  end

  def new
    @showroom = Showroom.new
    authorize @showroom
  end

  def create
    @showroom = Showroom.new(showroom_params)
    @showroom.delivery_address = build_or_update_address(@showroom.delivery_address)
    authorize @showroom
    if @showroom.save
      redirect_to admin_showrooms_path, notice: "Showroom '#{@showroom.name}' creado correctamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @showroom
  end

  def update
    @showroom.assign_attributes(showroom_params)
    @showroom.delivery_address = build_or_update_address(@showroom.delivery_address)
    authorize @showroom
    if @showroom.save
      redirect_to admin_showrooms_path, notice: "Showroom '#{@showroom.name}' actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @showroom
    @showroom.destroy
    redirect_to admin_showrooms_path, notice: "Showroom eliminado."
  end

  private

  def require_admin!
    redirect_to root_path, alert: "No autorizado" unless current_user.admin? || current_user.manager?
  end

  def set_showroom
    @showroom = Showroom.find(params[:id])
  end

  def showroom_params
    p = params.require(:showroom).permit(
      :name, :code, :is_main,
      :order_number_prefixes_raw,
      :order_number_keywords_raw,
      :inter_sala_keywords_raw,
      :product_keywords_raw
    )
    p[:order_number_prefixes] = parse_keywords(p.delete(:order_number_prefixes_raw))
    p[:order_number_keywords] = parse_keywords(p.delete(:order_number_keywords_raw))
    p[:inter_sala_keywords]   = parse_keywords(p.delete(:inter_sala_keywords_raw))
    p[:product_keywords]      = parse_keywords(p.delete(:product_keywords_raw))
    p
  end

  def address_attrs
    params.dig(:showroom, :delivery_address_attributes)
  end

  def build_or_update_address(existing)
    attrs = address_attrs
    return existing if attrs.blank? || attrs[:address].blank?

    client = Client.find_or_create_by!(name: "NaLakalu Showrooms") do |c|
      c.email = "showrooms@nalakalu.com"
      c.phone  = "0000-0000"
    end

    address = existing || client.delivery_addresses.build
    address.client  = client
    address.address = attrs[:address]
    address.description = attrs[:description].presence
    address.latitude    = attrs[:latitude].presence
    address.longitude   = attrs[:longitude].presence
    address.plus_code   = attrs[:plus_code].presence
    address
  end

  def parse_keywords(raw)
    return [] if raw.blank?
    raw.split(",").map(&:strip).reject(&:blank?)
  end
end
