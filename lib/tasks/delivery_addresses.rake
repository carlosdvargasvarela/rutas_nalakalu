namespace :delivery_addresses do
  desc "Rellena provincia/cantón/distrito (Google) en direcciones que aún no los tienen"
  task backfill_zone: :environment do
    DeliveryAddress.where(province: nil).where.not(address: [nil, ""]).find_each do |a|
      a.send(:geocode_enriched)
      a.update_columns(province: a.province, canton: a.canton, district: a.district)
    end
  end
end
