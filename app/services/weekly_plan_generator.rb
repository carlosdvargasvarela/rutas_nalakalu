# app/services/weekly_plan_generator.rb
class WeeklyPlanGenerator
  def initialize(week, year)
    @week = week
    @year = year
    @start_date = Date.commercial(year, week, 1) # Lunes de la semana
    @end_date = Date.commercial(year, week, 7)   # Domingo de la semana
  end

  def generate_plan
    plan = DeliveryPlan.create!(
      week: @week,
      year: @year,
      status: :draft
    )

    # Buscar entregas programadas para esa semana
    deliveries = Delivery.for_week(@start_date, @end_date)
                        .where(status: :scheduled)

    # Agregar entregas al plan
    deliveries.each do |delivery|
      plan.add_delivery(delivery)
    end

    plan
  end

  def generate_by_seller
    # Generar planes separados por vendedor
    plans = {}

    Seller.joins(orders: { deliveries: :delivery_items })
          .where(orders: { deliveries: { delivery_date: @start_date..@end_date } })
          .distinct
          .each do |seller|
      plan = DeliveryPlan.create!(
        week: "#{@week}-#{seller.seller_code}",
        year: @year,
        status: :draft
      )

      seller_deliveries = seller.orders
                                .joins(:deliveries)
                                .where(deliveries: { delivery_date: @start_date..@end_date })
                                .map(&:deliveries)
                                .flatten

      seller_deliveries.each { |delivery| plan.add_delivery(delivery) }
      plans[seller.seller_code] = plan
    end

    plans
  end
end
