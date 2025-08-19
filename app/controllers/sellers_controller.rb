# app/controllers/sellers_controller.rb
class SellersController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize Seller
    @q = policy_scope(Seller).ransack(params[:q])
    @sellers = @q.result.includes(:user).order(created_at: :desc).page(params[:page]).per(25)
  end

  def show
    @seller = Seller.find(params[:id])
    authorize @seller
    @orders = @seller.orders.includes(:client).order(created_at: :desc).page(params[:orders_page]).per(10)
  end
end
