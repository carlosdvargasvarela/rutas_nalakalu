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

ActiveRecord::Schema[7.2].define(version: 2025_09_04_200445) do
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

  create_table "clients", force: :cascade do |t|
    t.string "name"
    t.string "phone"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["delivery_address_id"], name: "index_deliveries_on_delivery_address_id"
    t.index ["delivery_type"], name: "index_deliveries_on_delivery_type"
    t.index ["order_id"], name: "index_deliveries_on_order_id"
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
    t.index ["client_id"], name: "index_delivery_addresses_on_client_id"
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
    t.index ["delivery_id"], name: "index_delivery_items_on_delivery_id"
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
    t.index ["delivery_id"], name: "index_delivery_plan_assignments_on_delivery_id"
    t.index ["delivery_plan_id"], name: "index_delivery_plan_assignments_on_delivery_plan_id"
    t.index ["status"], name: "index_delivery_plan_assignments_on_status"
  end

  create_table "delivery_plans", force: :cascade do |t|
    t.string "week"
    t.integer "year"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "driver_id"
    t.index ["driver_id"], name: "index_delivery_plans_on_driver_id"
  end

  create_table "driver_sessions", force: :cascade do |t|
    t.integer "driver_id", null: false
    t.integer "delivery_plan_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "start_time"
    t.datetime "end_time"
    t.decimal "current_latitude", precision: 10, scale: 6
    t.decimal "current_longitude", precision: 10, scale: 6
    t.datetime "last_reported_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_plan_id"], name: "index_driver_sessions_on_delivery_plan_id"
    t.index ["driver_id", "delivery_plan_id"], name: "index_driver_sessions_on_driver_id_and_delivery_plan_id", unique: true
    t.index ["driver_id"], name: "index_driver_sessions_on_driver_id"
    t.index ["status"], name: "index_driver_sessions_on_status"
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

  create_table "order_items", force: :cascade do |t|
    t.integer "order_id", null: false
    t.string "product"
    t.integer "quantity"
    t.text "notes"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "confirmed"
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "number"
    t.integer "client_id", null: false
    t.integer "seller_id", null: false
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_orders_on_client_id"
    t.index ["seller_id"], name: "index_orders_on_seller_id"
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
    t.boolean "send_notifications", default: true, null: false
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
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "deliveries", "delivery_addresses"
  add_foreign_key "deliveries", "orders"
  add_foreign_key "delivery_addresses", "clients"
  add_foreign_key "delivery_import_rows", "delivery_imports"
  add_foreign_key "delivery_imports", "users"
  add_foreign_key "delivery_items", "deliveries"
  add_foreign_key "delivery_items", "order_items"
  add_foreign_key "delivery_plan_assignments", "deliveries"
  add_foreign_key "delivery_plan_assignments", "delivery_plans"
  add_foreign_key "delivery_plans", "users", column: "driver_id"
  add_foreign_key "driver_sessions", "delivery_plans"
  add_foreign_key "driver_sessions", "users", column: "driver_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "clients"
  add_foreign_key "orders", "sellers"
  add_foreign_key "sellers", "users"
end
