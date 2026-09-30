namespace :delivery_addresses do
  desc "Rellena provincia/cantón/distrito (Google, por coordenadas) en direcciones que aún no los tienen"
  task backfill_zone: :environment do
    $stdout.sync = true
    scope = DeliveryAddress.where(province: nil)
    total = scope.count
    puts "Procesando #{total} direcciones..."
    scope.find_each.with_index(1) do |a, i|
      a.refresh_zone
      a.update_columns(province: a.province, canton: a.canton, district: a.district)
      puts "[#{i}/#{total}] ##{a.id} #{[a.province, a.canton, a.district].compact.join(" / ").presence || "(sin datos)"}"
    end
    puts "Listo."
  end
end
