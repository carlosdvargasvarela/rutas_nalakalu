# config/initializers/geocoder.rb
Geocoder.configure(
  lookup: :google,
  api_key: ENV["GOOGLE_MAPS_API_KEY"],
  use_https: true,
  language: :es,
  params: {
    region: "cr",            # Sesgo por Costa Rica
    components: "country:CR" # Restringe a CR
  },
  timeout: 5,
  units: :km
)
