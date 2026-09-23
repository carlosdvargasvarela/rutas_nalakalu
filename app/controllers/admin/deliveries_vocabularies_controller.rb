class Admin::DeliveriesVocabulariesController < ApplicationController
  SERVICE_TYPE_KEYS = Deliveries::Vocabulary::DEFAULT_SERVICE_TYPES.keys.freeze

  KEYWORD_LISTS = [
    {detector: "sala_pickup", list_name: "phrase_keywords", title: "Retiro en sala/tienda — frases que activan la detección",
     hint: "Un producto con alguna de estas frases (o un código SP/SE/SG) queda Pendiente de retiro en Sala."},
    {detector: "sala_pickup", list_name: "exclusions", title: "Retiro en sala/tienda — frases que excluyen (ya entregado)",
     hint: "Si el producto contiene alguna de estas frases se ignora (ya se entregó en sala)."},
    {detector: "service_case", list_name: "keywords", title: "Caso de servicio",
     hint: "Un producto con alguna de estas frases se marca como Caso de servicio. Evita palabras genéricas como \"error\"."},
    {detector: "repair_service", list_name: "keywords", title: "Servicio de reparación",
     hint: "Un producto con alguna de estas frases se marca como Servicio de reparación."},
    {detector: "showroom", list_name: "inter_sala_fallback_keywords", title: "Movimiento entre showrooms (fallback)",
     hint: "Frases que identifican un movimiento entre salas cuando no hay otra señal."}
  ].freeze

  def show
    authorize :deliveries_vocabulary, :show?
    load_view_data
  end

  def update
    authorize :deliveries_vocabulary, :update?

    ActiveRecord::Base.transaction do
      SERVICE_TYPE_KEYS.each do |key|
        attrs = params.dig(:service_types, key) || {}
        ServiceTypeWord.find_or_initialize_by(key: key).update!(
          label: attrs[:label].to_s.strip,
          prefix: attrs[:prefix].to_s
        )
      end

      KEYWORD_LISTS.each do |entry|
        raw = params.dig(:keyword_lists, entry[:detector], entry[:list_name])
        DetectorKeywordList.find_or_initialize_by(detector: entry[:detector], list_name: entry[:list_name])
          .update!(values_list: parse_keywords(raw))
      end
    end

    redirect_to admin_deliveries_vocabulary_path, notice: "Vocabulario actualizado correctamente."
  rescue ActiveRecord::RecordInvalid => e
    load_view_data
    flash.now[:alert] = "No se pudo guardar: #{e.message}"
    render :show, status: :unprocessable_entity
  end

  private

  def load_view_data
    @service_types = Deliveries::Vocabulary.service_types
    @keyword_lists = KEYWORD_LISTS.map do |entry|
      entry.merge(values: Deliveries::Vocabulary.detector_keywords(entry[:detector]).fetch(entry[:list_name]))
    end
  end

  def parse_keywords(raw)
    return [] if raw.blank?
    raw.split(/[\n,]/).map { |kw| Deliveries::Vocabulary.normalize(kw) }.reject(&:blank?).uniq
  end
end
