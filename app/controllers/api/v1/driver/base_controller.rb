module Api
  module V1
    module Driver
      class BaseController < ApplicationController
        include ApiTokenAuthenticatable
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :check_maintenance_mode, raise: false
        skip_before_action :check_password_change, raise: false
        skip_after_action :verify_authorized, raise: false
        skip_after_action :verify_policy_scoped, raise: false
        protect_from_forgery with: :null_session
      end
    end
  end
end
