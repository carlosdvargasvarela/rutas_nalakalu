# app/services/deliveries/vocabulary.rb
module Deliveries
  # Fuente única de las palabras de servicio (Recolección/Devolución/...) y de
  # las listas de palabras clave que usan los *_detector.rb para clasificar
  # texto libre. Editable desde /admin/deliveries_vocabulary
  # (ServiceTypeWord y DetectorKeywordList).
  #
  # Los DEFAULT_* de abajo son el valor de fábrica (igual que AppSetting.get
  # usa `default:`): garantizan que la app funcione en una base de datos
  # recién creada (test, clon nuevo) sin depender de seeds, y la fila en BD
  # —si existe— siempre gana sobre el default.
  #
  # CODE_PATTERN/SALA_MAP quedan en código porque son un detalle técnico
  # (regex) y datos sin uso real, no palabras de negocio editables.
  module Vocabulary
    CODE_PATTERN = '\b(SP|SE|SG)\b'
    SALA_MAP = {
      "SP" => "Sala Palmares",
      "SE" => "Sala Escazú",
      "SG" => "Sala Guanacaste"
    }.freeze

    DEFAULT_SERVICE_TYPES = {
      "recoleccion" => {"label" => "Recolección", "prefix" => "Recolección - "},
      "devolucion" => {"label" => "Devolución", "prefix" => "Devolución - "},
      "reparacion" => {"label" => "Reparación en sitio", "prefix" => "Reparación - "},
      "retiro" => {"label" => "Retiro", "prefix" => "Retiro - "},
      "entrega" => {"label" => "Entrega", "prefix" => ""},
      "cancelacion" => {"label" => "Cancelación", "prefix" => ""}
    }.freeze

    DEFAULT_DETECTOR_KEYWORDS = {
      "sala_pickup" => {
        "phrase_keywords" => ["recoger de sala", "pendiente sp", "pendiente se", "pendiente sg", "tienda"],
        "exclusions" => ["entregado en sala", "entregado en sp", "entregado en se", "entregado en sg",
          "entregado sp", "entregado se", "entregado sg", "entregado en tienda", "entregado tienda"]
      },
      "service_case" => {"keywords" => ["caso de servicio", "caso servicio"]},
      "repair_service" => {"keywords" => ["servicio de reparacion", "servicio reparacion"]},
      "showroom" => {"inter_sala_fallback_keywords" => ["entre salas"]},
      "assembly_buffer" => {"minutes" => []}
    }.freeze

    class << self
      def service_type_label(key)
        service_type(key).fetch("label")
      end

      def service_type_prefix(key)
        service_type(key).fetch("prefix")
      end

      def service_types
        DEFAULT_SERVICE_TYPES.keys.index_with { |key| service_type(key) }
      end

      def detector_keywords(detector)
        defaults = DEFAULT_DETECTOR_KEYWORDS.fetch(detector.to_s, {})
        overrides = DetectorKeywordList.where(detector: detector.to_s)
          .each_with_object({}) { |row, hash| hash[row.list_name] = row.values_list }

        lists = defaults.merge(overrides).transform_values { |list| list.map { |kw| normalize(kw) }.uniq }
        detector.to_s == "sala_pickup" ? lists.merge("code_pattern" => CODE_PATTERN, "sala_map" => SALA_MAP) : lists
      end

      # Los detectores comparan contra texto sin tildes y en minúsculas, así que
      # las palabras clave se guardan/leen en esa misma forma.
      def normalize(text)
        text.to_s.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").strip
      end

      private

      def service_type(key)
        key = key.to_s
        word = ServiceTypeWord.find_by(key: key)
        return {"label" => word.label, "prefix" => word.prefix} if word

        DEFAULT_SERVICE_TYPES.fetch(key)
      end
    end
  end
end
