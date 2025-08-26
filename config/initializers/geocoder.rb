# config/initializers/geocoder.rb
Geocoder.configure(
  lookup: :google,
  api_key: "AIzaSyBGqLJVEomqQc4qRA1_6Sp7clVxRZCbAno",
  use_https: true,
  units: :km,
  timeout: 5,
  language: :es # mejor precisión para Costa Rica en español
)
