# app/controllers/clients_controller.rb
class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: [ :show, :edit, :update, :destroy ]

  def index
    authorize Client
    @q = policy_scope(Client).ransack(params[:q])
    @clients = @q.result.order(created_at: :desc).page(params[:page]).per(25)
  end

  def show
    authorize @client
    @delivery_addresses = @client.delivery_addresses.order(created_at: :desc)
    @orders = @client.orders.includes(:seller).order(created_at: :desc).page(params[:orders_page]).per(10)
  end

  def new
    @client = Client.new
    authorize @client
  end

  def create
    @client = Client.new(client_params)
    authorize @client
    if @client.save
      redirect_to @client, notice: "Cliente creado correctamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @client
  end

  def update
    authorize @client
    if @client.update(client_params)
      redirect_to @client, notice: "Cliente actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @client
    if @client.orders.exists? || @client.delivery_addresses.exists?
      redirect_to @client, alert: "No se puede eliminar el cliente porque tiene pedidos o direcciones asociadas."
    else
      @client.destroy
      redirect_to clients_path, notice: "Cliente eliminado."
    end
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name, :phone, :email)
  end
end
