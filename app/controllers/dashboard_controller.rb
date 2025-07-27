# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def index
    @current_user_role = current_user.role
  end
end