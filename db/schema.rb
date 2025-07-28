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

ActiveRecord::Schema[7.2].define(version: 2025_07_27_233341) do
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
    t.index ["client_id"], name: "index_delivery_addresses_on_client_id"
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
    t.index ["delivery_id"], name: "index_delivery_plan_assignments_on_delivery_id"
    t.index ["delivery_plan_id"], name: "index_delivery_plan_assignments_on_delivery_plan_id"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "deliveries", "delivery_addresses"
  add_foreign_key "deliveries", "orders"
  add_foreign_key "delivery_addresses", "clients"
  add_foreign_key "delivery_items", "deliveries"
  add_foreign_key "delivery_items", "order_items"
  add_foreign_key "delivery_plan_assignments", "deliveries"
  add_foreign_key "delivery_plan_assignments", "delivery_plans"
  add_foreign_key "delivery_plans", "users", column: "driver_id"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "clients"
  add_foreign_key "orders", "sellers"
  add_foreign_key "sellers", "users"
end
