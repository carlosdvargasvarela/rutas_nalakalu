# app/helpers/iso_week_helper.rb
module IsoWeekHelper
  # Retorna el rango [start_date, end_date] de la próxima semana ISO
  def self.next_iso_week_range(from_date = Date.current)
    # Calcular inicio de la próxima semana ISO (lunes)
    next_monday = from_date.next_occurring(:monday)

    # Fin de esa semana (domingo)
    next_sunday = next_monday + 6.days

    [next_monday, next_sunday]
  end

  # Retorna el rango [start_date, end_date] de la semana ISO actual
  def self.current_iso_week_range(from_date = Date.current)
    start_of_week = from_date.beginning_of_week(:monday)
    end_of_week = from_date.end_of_week(:monday)

    [start_of_week, end_of_week]
  end

  # Verifica si una fecha está en la semana ISO actual
  def self.in_current_iso_week?(date, reference_date = Date.current)
    start_date, end_date = current_iso_week_range(reference_date)
    date.between?(start_date, end_date)
  end
end
