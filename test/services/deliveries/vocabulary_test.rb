require "test_helper"

module Deliveries
  class VocabularyTest < ActiveSupport::TestCase
    setup do
      ServiceTypeWord.delete_all
      DetectorKeywordList.delete_all
    end

    test "service_type_label falls back to the factory default when no row exists" do
      assert_equal "Recolección", Vocabulary.service_type_label("recoleccion")
    end

    test "service_type_label uses the DB override when present" do
      ServiceTypeWord.create!(key: "recoleccion", label: "Pickup", prefix: "Pickup - ")

      assert_equal "Pickup", Vocabulary.service_type_label("recoleccion")
      assert_equal "Pickup - ", Vocabulary.service_type_prefix("recoleccion")
    end

    test "service_types lists every default key even without DB rows" do
      assert_equal Vocabulary::DEFAULT_SERVICE_TYPES.keys.sort, Vocabulary.service_types.keys.sort
    end

    test "detector_keywords falls back to factory defaults when no row exists" do
      assert_equal ["caso de servicio", "caso servicio"],
        Vocabulary.detector_keywords("service_case").fetch("keywords")
    end

    test "detector_keywords uses the DB override when present" do
      DetectorKeywordList.create!(detector: "service_case", list_name: "keywords", values_list: ["palabra custom"])

      assert_equal ["palabra custom"], Vocabulary.detector_keywords("service_case").fetch("keywords")
    end

    test "detector_keywords for sala_pickup merges DB overrides with the technical code_pattern/sala_map" do
      DetectorKeywordList.create!(detector: "sala_pickup", list_name: "phrase_keywords", values_list: ["custom"])

      result = Vocabulary.detector_keywords("sala_pickup")

      assert_equal ["custom"], result.fetch("phrase_keywords")
      assert_equal Vocabulary::DEFAULT_DETECTOR_KEYWORDS.fetch("sala_pickup").fetch("exclusions"),
        result.fetch("exclusions")
      assert_equal Vocabulary::CODE_PATTERN, result.fetch("code_pattern")
      assert_equal Vocabulary::SALA_MAP, result.fetch("sala_map")
    end
  end
end
