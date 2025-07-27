# db/seeds.rb

# Clean up previous data
DeliveryPlanAssignment.delete_all
DeliveryPlan.delete_all
DeliveryItem.delete_all
Delivery.delete_all
OrderItem.delete_all
Order.delete_all
DeliveryAddress.delete_all
Client.delete_all
Seller.delete_all
User.delete_all

puts "Cleaning up previous data..."

# Users
admin = User.create!(
  name: "Admin User",
  email: "admin@nalakalu.com",
  password: "password123",
  role: :admin
)

prod_manager = User.create!(
  name: "Maria Production",
  email: "production@nalakalu.com",
  password: "password123",
  role: :production_manager
)

# Crear usuarios vendedores
seller_user1 = User.create!(
  name: "Nathaly García",
  email: "ngarcia@nalakalu.com",
  password: "password123",
  role: :seller
)

seller_user2 = User.create!(
  name: "Carolina Matamoros",
  email: "cmatamoros@nalakalu.com",
  password: "password123",
  role: :seller
)

seller_user3 = User.create!(
  name: "Andrea Chavarría",
  email: "luis@nalakalu.com",
  password: "password123",
  role: :seller
)

logistics_user = User.create!(
  name: "Ana Logistics",
  email: "logistics@nalakalu.com",
  password: "password123",
  role: :logistics
)

puts "Users created..."

# Sellers con códigos comunes
seller1 = Seller.create!(
  user: seller_user1,
  name: seller_user1.name,
  seller_code: "NGA"
)

seller2 = Seller.create!(
  user: seller_user2,
  name: seller_user2.name,
  seller_code: "CMC"
)

seller3 = Seller.create!(
  user: seller_user3,
  name: seller_user3.name,
  seller_code: "ACA"
)

# Agregar más códigos que podrían estar en tu Excel
additional_sellers = [
  { code: "CV", name: "Carlos Vargas" },
  { code: "AL", name: "Ana López" },
  { code: "MR", name: "Mario Rodríguez" },
  { code: "JS", name: "José Solano" },
  { code: "LM", name: "Laura Morales" }
]

additional_sellers.each do |seller_data|
  # Crear usuario para cada vendedor adicional
  user = User.create!(
    name: seller_data[:name],
    email: "#{seller_data[:code].downcase}@nalakalu.com",
    password: "password123",
    role: :seller
  )

  Seller.create!(
    user: user,
    name: seller_data[:name],
    seller_code: seller_data[:code]
  )
end

puts "Sellers created with codes: #{Seller.pluck(:seller_code).join(', ')}"

# Algunos clientes de ejemplo
client1 = Client.create!(
  name: "Muebles La Casa",
  phone: "8888-1111",
  email: "contacto@lacasacr.com"
)

client2 = Client.create!(
  name: "Oficinas XYZ",
  phone: "2222-3333",
  email: "compras@xyz.com"
)

puts "Sample clients created..."

puts "Seeds loaded successfully!"
puts "Available seller codes: #{Seller.pluck(:seller_code)}"
