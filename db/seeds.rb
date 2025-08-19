# db/seeds.rb

puts "Limpiando datos previos..."

# Limpieza en orden para respetar FKs
DeliveryPlanAssignment.delete_all
DeliveryPlan.delete_all
DeliveryItem.delete_all
Delivery.delete_all
OrderItem.delete_all
Order.delete_all
DeliveryAddress.delete_all
Client.delete_all
Notification.delete_all if defined?(Notification)
Seller.delete_all
User.delete_all
PaperTrail::Version.delete_all if defined?(PaperTrail::Version)

puts "Cargando usuarios..."

DEFAULT_PASSWORD = "Nalakalu.01"

# =========================
# Ventas (Users + Sellers)
# =========================
sales_people = [
  { code: "ACA", name: "Andrea Chavarría", email: "achavarria@nalakalu.com" },
  { code: "JMR", name: "Jose Mario Rodríguez", email: "jmrodriguez@nalakalu.com" },
  { code: "ARA", name: "Ana Rojas", email: "arojas@nalakalu.com" },
  { code: "GAM", name: "Guadalupe Arguedas", email: "garguedas@nalakalu.com" },
  { code: "MAQ", name: "Melissa Araya", email: "maraya@nalakalu.com" },
  { code: "MG",  name: "Maricia Gutiérrez", email: "mgutierrez@nalakalu.com" },
  { code: "MMM", name: "Marcela Muñoz", email: "mmunoz@nalakalu.com" },
  { code: "NGA", name: "Nathaly Garcia", email: "ngarcia@nalakalu.com" },
  { code: "SFM", name: "Sabrina Fernández", email: "sfernandez@nalakalu.com" },
  { code: "NFH", name: "Nadja Fernandez", email: "nfernandez@nalakalu.com" },
  { code: "ERF", name: "Estefanía Rojas", email: "erojas@nalakalu.com" },
  { code: "CMC", name: "Carolina Matamoros", email: "cmatamoros@nalakalu.com" },
  { code: "KCC", name: "Katia Castro", email: "kcastro@nalakalu.com" },
  { code: "PCV", name: "Pablo Chaves", email: "pchaves@nalakalu.com" },
  { code: "KSA", name: "Karol Segura", email: "ksegura@nalakalu.com" },
  { code: "ARR", name: "Amanda Rodriguez", email: "arodriguez@nalakalu.com" },
  { code: "NRM", name: "Nelson Rodriguez", email: "nrodriguez@nalakalu.com" },
  { code: "ALH", name: "Alina Lopez Hidalgo", email: "alopez@nalakalu.com" },
  { code: "ISA", name: "Ileana Salas Arce", email: "isalas@nalakalu.com" },
  { code: "RES", name: "Rebeca Esquivel Sandoval", email: "resquivel@nalakalu.com" }
]

sales_people.each do |s|
  user = User.create!(
    name: s[:name],
    email: s[:email],
    password: DEFAULT_PASSWORD,
    role: :seller,
    seller_code: s[:code]
  )
  Seller.create!(
    user: user,
    name: s[:name],
    seller_code: s[:code]
  )
end

puts "Vendedores creados: #{Seller.count} (códigos: #{Seller.pluck(:seller_code).join(', ')})"

# =========================
# Production Managers
# =========================
production_managers = [
  { name: "Nathalia Rocha", email: "nrocha@nalakalu.com" },
  { name: "Carlos Cordoba", email: "ccordoba@nalakalu.com" },
  { name: "Andres Moya",   email: "amoya@nalakalu.com" }
]

production_managers.each do |pm|
  User.create!(
    name: pm[:name],
    email: pm[:email],
    password: DEFAULT_PASSWORD,
    role: :production_manager
  )
end
puts "Production managers creados: #{production_managers.size}"

# =========================
# Administradores
# =========================
admins = [
  { name: "Carlos Vargas", email: "cvargas@nalakalu.com" },
  { name: "Juan Castillo", email: "jcastillo@nalakalu.com" },
  { name: "Maria Arias",   email: "marias@nalakalu.com" },
  { name: "Klariza Araya", email: "karaya@nalakalu.com" }
]

admins.each do |a|
  user = User.create!(
    name: a[:name],
    email: a[:email],
    password: DEFAULT_PASSWORD,
    role: :admin
  )
  if user.name == "Juan Castillo"
    Seller.create!(
    user: user,
    name: a[:name],
    seller_code: "JCR"
  )
  end
end
puts "Admins creados: #{admins.size}"

# =========================
# Logística
# =========================
logistics = [
  { name: "Ricardo Castillo", email: "rcastillo@nalakalu.com" },
  { name: "Danny Castillo",   email: "dcastillo@nalakalu.com" },
  { name: "Rubén Quirós",     email: "rquiros@nalakalu.com" }
]

logistics.each do |l|
  User.create!(
    name: l[:name],
    email: l[:email],
    password: DEFAULT_PASSWORD,
    role: :driver
  )
end

puts "Seeds cargados correctamente."
puts "Total usuarios: #{User.count} | Sellers: #{Seller.count}"
puts "Contraseña por defecto para todos: #{DEFAULT_PASSWORD}"