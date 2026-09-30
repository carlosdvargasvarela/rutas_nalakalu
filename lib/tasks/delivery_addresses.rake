namespace :delivery_addresses do
  desc "Rellena provincia/cantón/distrito (Google) de direcciones con entregas desde el 1 de enero de este año"
  task backfill_zone: :environment do
    $stdout.sync = true
    ids = Delivery.where(delivery_date: Date.current.beginning_of_year..).select(:delivery_address_id)
    scope = DeliveryAddress.where(id: ids).where(province: nil).or(DeliveryAddress.where(id: ids).where(canton: nil)).or(DeliveryAddress.where(id: ids).where(district: nil))
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
