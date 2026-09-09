# app/models/order_contact.rb
class OrderContact < ApplicationRecord
  has_paper_trail

  belongs_to :order

  include HasPrimaryContact
end
