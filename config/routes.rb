require "sidekiq/web"

Rails.application.routes.draw do
  # =============================================================================
  # SIDEKIQ WEB PANEL - Monitoreo de jobs en background
  # =============================================================================
  # Panel web para monitorear jobs, colas y scheduler de Sidekiq
  # Accesible en: /sidekiq

  # Panel Sidekiq solo en desarrollo (sin autenticación)
  if Rails.env.development?
    mount Sidekiq::Web => "/sidekiq"
  else
    # En producción, solo para admins autenticados
    authenticate :user, lambda { |u| u.admin? } do
      mount Sidekiq::Web => "/sidekiq"
    end
  end

  # =============================================================================
  # RUTAS DE SALUD Y PWA
  # =============================================================================
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  # Rutas PWA
  get "/manifest.json", to: "pwa#manifest", as: :pwa_manifest
  get "/service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker

  # =============================================================================
  # AUTENTICACIÓN DE USUARIOS
  # =============================================================================
  # Devise routes for user authentication
  # Genera rutas como: /users/sign_in, /users/sign_up, /users/sign_out, etc.
  devise_for :users

  # =============================================================================
  # RUTA PRINCIPAL
  # =============================================================================
  # Define the root path of the application
  root "dashboard#index"

  # =============================================================================
  # DASHBOARD
  # =============================================================================
  # Panel principal con métricas y resumen
  resources :dashboard, only: [ :index ]

  # =============================================================================
  # ENTREGAS (DELIVERIES)
  # =============================================================================
  # Gestión completa de entregas de muebles
  resources :deliveries, only: [ :index, :show, :new, :create, :edit, :update ] do
    collection do
      get :by_week
      get :service_cases
      get :addresses_for_client
      get :orders_for_client

      # Mandados internos
      get  :new_internal_delivery
      post :create_internal_delivery

      # Casos de servicio "nuevos", globales
      get  :new_service_case
      post :create_service_case
    end

    member do
      patch :mark_as_delivered
      patch :confirm_all_items
      patch :reschedule_all

      patch :approve

      get :note

      patch :archive

      # ✅ Casos de servicio derivados de una entrega existente
      get  :new_service_case_for_existing
      post :create_service_case_for_existing
    end
  end

  # =============================================================================
  # ITEMS DE PEDIDOS (ORDER ITEMS)
  # =============================================================================
  # Confirmación individual de items en pedidos
  resources :order_items, only: [] do
    member do
      patch :confirm
      patch :unconfirm
    end

    resources :order_item_notes, except: [ :index, :show ] do
      member do
        patch :close
        patch :reopen
      end
    end
  end

  # =============================================================================
  # ITEMS DE ENTREGA (DELIVERY ITEMS)
  # =============================================================================
  # Gestión del estado de items individuales en entregas
  resources :delivery_items, only: [ :show ] do
    member do
      patch :confirm
      patch :mark_delivered
      patch :reschedule
      patch :cancel
      patch :update_notes
    end
    collection do
      post :bulk_add_notes
    end
  end

  # =============================================================================
  # PLANES DE ENTREGA (DELIVERY PLANS)
  # =============================================================================
  # Planificación semanal de rutas de entrega
  resources :delivery_plans, only: [ :index, :show, :new, :create, :edit, :update ] do
    member do
      patch :add_delivery_to_plan # Agregar entrega al plan
      patch :send_to_logistics    # Enviar plan a logística
      patch :update_order         # Actualizar orden en el plan
    end
    # Asignaciones de entregas a planes (para eliminar)
    resources :delivery_plan_assignments, only: [ :destroy ]
  end

  # =============================================================================
  # IMPORTACIÓN DE ENTREGAS
  # =============================================================================
  # Importar entregas desde archivos Excel
  resources :delivery_imports, only: [ :new, :create, :show ] do
    member do
      patch :update_rows    # guardar ediciones en las filas
      post :process_import  # lanzar import final
    end
    collection do
      get :template         # bajar plantilla excel
    end
  end

  # =============================================================================
  # NOTIFICACIONES
  # =============================================================================
  # Sistema de notificaciones para usuarios
  resources :notifications, only: [ :index ] do
  member do
      patch :mark_as_read
    end
    collection do
      patch :mark_all_as_read
      patch :mark_group_as_read
    end
  end

  # =============================================================================
  # PEDIDOS (ORDERS)
  # =============================================================================
  # Visualización y gestión de pedidos
  resources :orders, only: [ :index, :show, :destroy ] do
    member do
      patch :confirm_all_items_ready
    end
  end

  # =============================================================================
  # CLIENTES Y VENDEDORES
  # =============================================================================
  # Información de clientes y vendedores (solo lectura)
  resources :clients, only: [ :index, :show, :edit, :update, :new, :create ]
  resources :sellers, only: [ :index, :show ]

  # =============================================================================
  # DIRECCIONES DE ENTREGA
  # =============================================================================
  # Creación de nuevas direcciones de entrega
  resources :delivery_addresses, only: [ :create ]

  namespace :admin do
    resources :users, only: [ :index, :new, :create, :edit, :update ] do
      member do
        post :send_reset_password
        patch :unlock
        patch :toggle_notifications
      end
    end
  end
  # =============================================================================
  # MODO CHOFER (Driver)
  # =============================================================================
  namespace :driver do
    resources :delivery_plans, only: [ :index, :show ] do
      member do
        patch :update_position
        patch :start
        patch :finish
        patch :abort
      end

      resources :assignments, only: [] do
        member do
          patch :start
          patch :complete
          patch :mark_failed
          patch :note
        end
      end
    end
  end

  get "/offline", to: "pages#offline"
end
