class Admin::ShowroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_showroom, only: [:edit, :update, :destroy]

  def index
    @showrooms = Showroom.includes(:delivery_address).order(:name)
  end

  def new
    @showroom = Showroom.new
    @addresses = DeliveryAddress.order(:address).limit(200)
  end

  def create
    @showroom = Showroom.new(showroom_params)
    if @showroom.save
      redirect_to admin_showrooms_path, notice: "Showroom '#{@showroom.name}' creado correctamente."
    else
      @addresses = DeliveryAddress.order(:address).limit(200)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @addresses = DeliveryAddress.order(:address).limit(200)
  end

  def update
    if @showroom.update(showroom_params)
      redirect_to admin_showrooms_path, notice: "Showroom '#{@showroom.name}' actualizado correctamente."
    else
      @addresses = DeliveryAddress.order(:address).limit(200)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
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
      :name, :code, :delivery_address_id, :is_main,
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

  def parse_keywords(raw)
    return [] if raw.blank?
    raw.split(",").map(&:strip).reject(&:blank?)
  end
end
