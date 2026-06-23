# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_06_19_222548) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "client_notes", force: :cascade do |t|
    t.integer "client_id", null: false
    t.integer "user_id", null: false
    t.text "body", null: false
    t.integer "category", default: 0, null: false
    t.boolean "pinned", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_client_notes_on_category"
    t.index ["client_id", "pinned"], name: "index_client_notes_on_client_id_and_pinned"
    t.index ["client_id"], name: "index_client_notes_on_client_id"
    t.index ["pinned"], name: "index_client_notes_on_pinned"
    t.index ["user_id"], name: "index_client_notes_on_user_id"
  end

  create_table "clients", force: :cascade do |t|
    t.string "name"
    t.string "phone"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "crew_members", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name"
    t.string "id_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_crew_members_on_user_id"
  end

  create_table "deliveries", force: :cascade do |t|
    t.integer "order_id", null: false
    t.integer "delivery_address_id", null: false
    t.date "delivery_date"
    t.string "contact_name"
    t.string "contact_phone"
    t.string "contact_id"
    t.integer "status"
    t.string "delivery_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "delivery_time_preference"
    t.integer "delivery_type", default: 0
    t.boolean "approved", default: true, null: false
    t.text "reschedule_reason"
    t.boolean "archived", default: false, null: false
    t.boolean "confirmed_by_vendor", default: false, null: false
    t.datetime "confirmed_by_vendor_at"
    t.integer "load_status", default: 0, null: false
    t.string "tracking_token"
    t.date "warehousing_until"
    t.string "condominio_number"
    t.string "casa_number"
    t.integer "source_showroom_id"
    t.integer "destination_showroom_id"
    t.index ["approved"], name: "index_deliveries_on_approved"
    t.index ["archived"], name: "index_deliveries_on_archived"
    t.index ["confirmed_by_vendor"], name: "index_deliveries_on_confirmed_by_vendor"
    t.index ["confirmed_by_vendor_at"], name: "index_deliveries_on_confirmed_by_vendor_at"
    t.index ["delivery_address_id"], name: "index_deliveries_on_delivery_address_id"
    t.index ["delivery_date"], name: "index_deliveries_on_delivery_date"
    t.index ["delivery_type"], name: "index_deliveries_on_delivery_type"
    t.index ["destination_showroom_id"], name: "index_deliveries_on_destination_showroom_id"
    t.index ["load_status"], name: "index_deliveries_on_load_status"
    t.index ["order_id"], name: "index_deliveries_on_order_id"
    t.index ["source_showroom_id"], name: "index_deliveries_on_source_showroom_id"
    t.index ["tracking_token"], name: "index_deliveries_on_tracking_token", unique: true
    t.index ["warehousing_until"], name: "index_deliveries_on_warehousing_until"
  end

  create_table "delivery_addresses", force: :cascade do |t|
    t.integer "client_id", null: false
    t.text "address"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "plus_code"
    t.string "place_id"
    t.string "normalized_address"
    t.string "geocode_quality"
    t.index ["client_id"], name: "index_delivery_addresses_on_client_id"
    t.index ["place_id"], name: "index_delivery_addresses_on_place_id"
  end

  create_table "delivery_events", force: :cascade do |t|
    t.integer "delivery_id", null: false
    t.string "action", null: false
    t.integer "actor_id"
    t.text "payload"
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_delivery_events_on_action"
    t.index ["actor_id"], name: "index_delivery_events_on_actor_id"
    t.index ["created_at"], name: "index_delivery_events_on_created_at"
    t.index ["delivery_id"], name: "index_delivery_events_on_delivery_id"
  end

  create_table "delivery_group_memberships", force: :cascade do |t|
    t.integer "delivery_group_id", null: false
    t.integer "delivery_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_group_id"], name: "index_delivery_group_memberships_on_delivery_group_id"
    t.index ["delivery_id"], name: "idx_dgm_unique_delivery", unique: true
    t.index ["delivery_id"], name: "index_delivery_group_memberships_on_delivery_id"
  end

  create_table "delivery_groups", force: :cascade do |t|
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "delivery_import_rows", force: :cascade do |t|
    t.integer "delivery_import_id", null: false
    t.text "data", default: "{}"
    t.text "row_errors", default: "[]"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_import_id"], name: "index_delivery_import_rows_on_delivery_import_id"
  end

  create_table "delivery_imports", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "status", default: 0
    t.text "import_errors"
    t.integer "success_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_delivery_imports_on_user_id"
  end

  create_table "delivery_items", force: :cascade do |t|
    t.integer "delivery_id", null: false
    t.integer "order_item_id", null: false
    t.integer "quantity_delivered"
    t.integer "status"
    t.boolean "service_case", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "notes"
    t.integer "load_status", default: 0, null: false
    t.integer "loaded_quantity"
    t.boolean "sala_pickup_requested", default: false, null: false
    t.index ["delivery_id", "order_item_id"], name: "index_delivery_items_on_delivery_and_order_item_unique", unique: true
    t.index ["delivery_id"], name: "index_delivery_items_on_delivery_id"
    t.index ["load_status"], name: "index_delivery_items_on_load_status"
    t.index ["order_item_id"], name: "index_delivery_items_on_order_item_id"
  end

  create_table "delivery_plan_assignments", force: :cascade do |t|
    t.integer "delivery_id", null: false
    t.integer "delivery_plan_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "stop_order"
    t.integer "status", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "driver_notes"
    t.integer "lock_version", default: 0, null: false
    t.index ["delivery_id"], name: "index_delivery_plan_assignments_on_delivery_id"
    t.index ["delivery_plan_id"], name: "index_delivery_plan_assignments_on_delivery_plan_id"
    t.index ["status"], name: "index_delivery_plan_assignments_on_status"
  end

  create_table "delivery_plan_locations", force: :cascade do |t|
    t.integer "delivery_plan_id", null: false
    t.decimal "latitude", precision: 10, scale: 7, null: false
    t.decimal "longitude", precision: 10, scale: 7, null: false
    t.float "speed"
    t.float "heading"
    t.float "accuracy"
    t.datetime "captured_at", null: false
    t.string "source", default: "live", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "recorded_at"
    t.index ["delivery_plan_id", "captured_at"], name: "index_locations_on_plan_and_captured_at"
    t.index ["delivery_plan_id"], name: "index_delivery_plan_locations_on_delivery_plan_id"
    t.index ["recorded_at"], name: "index_delivery_plan_locations_on_recorded_at"
  end

  create_table "delivery_plans", force: :cascade do |t|
    t.string "week"
    t.integer "year"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "driver_id"
    t.integer "truck"
    t.decimal "current_lat", precision: 10, scale: 6
    t.decimal "current_lng", precision: 10, scale: 6
    t.datetime "last_seen_at"
    t.decimal "current_speed", precision: 5, scale: 2
    t.decimal "current_heading", precision: 5, scale: 2
    t.decimal "current_accuracy", precision: 6, scale: 2
    t.integer "lock_version", default: 0, null: false
    t.integer "load_status", default: 0, null: false
    t.index ["driver_id"], name: "index_delivery_plans_on_driver_id"
    t.index ["last_seen_at"], name: "index_delivery_plans_on_last_seen_at"
    t.index ["load_status"], name: "index_delivery_plans_on_load_status"
  end

  create_table "detector_keyword_lists", force: :cascade do |t|
    t.string "detector", null: false
    t.string "list_name", null: false
    t.text "values_list", default: "[]", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["detector", "list_name"], name: "index_detector_keyword_lists_on_detector_and_list_name", unique: true
  end

  create_table "maintenance_windows", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "ends_at"
    t.integer "activated_by_id", null: false
    t.text "allowed_user_ids", default: "[]"
    t.string "message", default: "El sistema está en mantenimiento. Volvemos pronto."
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_maintenance_windows_on_active"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "notifiable_type", null: false
    t.integer "notifiable_id", null: false
    t.string "message", null: false
    t.boolean "read", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "notification_type"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable_type_and_notifiable_id"
    t.index ["user_id", "read"], name: "index_notifications_on_user_id_and_read"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "order_contacts", force: :cascade do |t|
    t.integer "order_id", null: false
    t.string "name", null: false
    t.string "phone"
    t.boolean "is_primary", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_contacts_on_order_id"
  end

  create_table "order_item_notes", force: :cascade do |t|
    t.integer "order_item_id", null: false
    t.integer "user_id", null: false
    t.text "body", null: false
    t.boolean "closed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_item_id"], name: "index_order_item_notes_on_order_item_id"
    t.index ["user_id"], name: "index_order_item_notes_on_user_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.integer "order_id", null: false
    t.string "product"
    t.integer "quantity"
    t.text "notes"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "confirmed"
    t.string "qb_line_id"
    t.index ["order_id", "product"], name: "index_order_items_on_order_and_product_unique", unique: true
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["qb_line_id"], name: "index_order_items_on_qb_line_id", unique: true
  end

  create_table "orders", force: :cascade do |t|
    t.string "number"
    t.integer "client_id", null: false
    t.integer "seller_id", null: false
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "qb_txn_id"
    t.datetime "qb_updated_at"
    t.index ["client_id"], name: "index_orders_on_client_id"
    t.index ["qb_txn_id"], name: "index_orders_on_qb_txn_id", unique: true
    t.index ["seller_id"], name: "index_orders_on_seller_id"
  end

  create_table "plan_events", force: :cascade do |t|
    t.integer "delivery_plan_id", null: false
    t.string "action", null: false
    t.integer "actor_id"
    t.text "payload"
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_plan_events_on_action"
    t.index ["actor_id"], name: "index_plan_events_on_actor_id"
    t.index ["created_at"], name: "index_plan_events_on_created_at"
    t.index ["delivery_plan_id"], name: "index_plan_events_on_delivery_plan_id"
  end

  create_table "qbwc_jobs", force: :cascade do |t|
    t.string "name"
    t.string "company", limit: 1000
    t.string "worker_class", limit: 100
    t.boolean "enabled", default: false, null: false
    t.text "request_index"
    t.text "requests"
    t.boolean "requests_provided_when_job_added", default: false, null: false
    t.text "data"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["company"], name: "index_qbwc_jobs_on_company"
    t.index ["name"], name: "index_qbwc_jobs_on_name", unique: true
  end

  create_table "qbwc_sessions", force: :cascade do |t|
    t.string "ticket"
    t.string "user"
    t.string "company", limit: 1000
    t.integer "progress", default: 0, null: false
    t.string "current_job"
    t.string "iterator_id"
    t.string "error", limit: 1000
    t.text "pending_jobs", limit: 1000, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "sellers", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name"
    t.string "seller_code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["seller_code"], name: "index_sellers_on_seller_code", unique: true
    t.index ["user_id"], name: "index_sellers_on_user_id"
  end

  create_table "service_type_words", force: :cascade do |t|
    t.string "key", null: false
    t.string "label", null: false
    t.string "prefix", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_service_type_words_on_key", unique: true
  end

  create_table "showrooms", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.integer "delivery_address_id"
    t.text "order_number_prefixes", default: "[]", null: false
    t.text "order_number_keywords", default: "[]", null: false
    t.text "inter_sala_keywords", default: "[]", null: false
    t.text "product_keywords", default: "[]", null: false
    t.boolean "is_main", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_showrooms_on_code", unique: true
    t.index ["delivery_address_id"], name: "index_showrooms_on_delivery_address_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", null: false
    t.integer "role", default: 0
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.boolean "force_password_change", default: true, null: false
    t.boolean "send_notifications", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.datetime "created_at"
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.text "object", limit: 1073741823
    t.text "object_changes", limit: 1073741823
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "client_notes", "clients"
  add_foreign_key "client_notes", "users"
  add_foreign_key "crew_members", "users"
  add_foreign_key "deliveries", "delivery_addresses"
  add_foreign_key "deliveries", "orders"
  add_foreign_key "deliveries", "showrooms", column: "destination_showroom_id"
  add_foreign_key "deliveries", "showrooms", column: "source_showroom_id"
  add_foreign_key "delivery_addresses", "clients"
  add_foreign_key "delivery_events", "deliveries", on_delete: :cascade
  add_foreign_key "delivery_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "delivery_group_memberships", "deliveries"
  add_foreign_key "delivery_group_memberships", "delivery_groups"
  add_foreign_key "delivery_import_rows", "delivery_imports"
  add_foreign_key "delivery_imports", "users"
  add_foreign_key "delivery_items", "deliveries"
  add_foreign_key "delivery_items", "order_items"
  add_foreign_key "delivery_plan_assignments", "deliveries", on_delete: :restrict
  add_foreign_key "delivery_plan_assignments", "delivery_plans", on_delete: :cascade
  add_foreign_key "delivery_plan_locations", "delivery_plans"
  add_foreign_key "delivery_plans", "users", column: "driver_id"
  add_foreign_key "maintenance_windows", "users", column: "activated_by_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "order_contacts", "orders"
  add_foreign_key "order_item_notes", "order_items"
  add_foreign_key "order_item_notes", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "clients"
  add_foreign_key "orders", "sellers"
  add_foreign_key "plan_events", "delivery_plans", on_delete: :cascade
  add_foreign_key "plan_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "sellers", "users"
  add_foreign_key "showrooms", "delivery_addresses"
end
