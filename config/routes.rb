Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Devise routes for user authentication
  devise_for :users

  # Define the root path of the application
  # Devise routes for user authentication
  root "dashboard#index"

  resources :dashboard, only: [ :index ]

  resources :deliveries, only: [ :index, :show, :new, :create, :edit, :update ] do
    collection do
      get :by_week # Para filtrar por semana
      get :service_cases # Para ver solo casos de servicio
      get :addresses_for_client
      get :orders_for_client
    end
    member do
      patch :mark_as_delivered
    end
  end

  # Puedes agregar rutas para otros modelos si quieres verlos
  resources :order_items, only: [] do
    member do
      patch :confirm
      patch :unconfirm
    end
  end

  resources :delivery_items, only: [ :show ] do
    member do
      patch :confirm
      patch :mark_delivered
      patch :reschedule
      patch :cancel
    end
  end

  resources :delivery_plans, only: [ :index, :show, :new, :create, :edit, :update ] do
    member do
      patch :add_delivery_to_plan
      patch :send_to_logistics
      patch :update_order
    end
    resources :delivery_plan_assignments, only: [ :destroy ]
  end

  resources :delivery_imports, only: [ :new ] do
    collection do
      post :preview
      post :process_import
      get :template
    end
  end

  resources :notifications, only: [ :index ] do
    member do
      patch :mark_as_read
    end
    collection do
      patch :mark_all_as_read
    end
  end

  resources :orders, only: [ :index, :show, :destroy ]
  resources :clients, only: [ :index, :show ]
  resources :sellers, only: [ :index, :show ]
  resources :delivery_addresses, only: [ :create ]
end
