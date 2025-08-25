# config/initializers/geocoder.rb
Geocoder.configure(
  lookup: :google,
  api_key: "AIzaSyAX1ME8q3c7LYFTdgyMYWAVclmPgRQ50Ek",
  use_https: true,
  units: :km,
  timeout: 5,
  language: :es # mejor precisión para Costa Rica en español
)
