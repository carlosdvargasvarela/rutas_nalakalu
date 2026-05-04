# config/initializers/qbxml_bigdecimal_patch.rb
require "bigdecimal"

Rails.application.config.after_initialize do
  Qbxml::Types.send(:remove_const, :BIGDECIMAL_CAST)
  Qbxml::Types.const_set(:BIGDECIMAL_CAST, proc do |d|
    if d
      BigDecimal(d.to_s.tr(",", "."))
    else
      BigDecimal(0)
    end
  end)

  # Actualizar el TYPE_MAP para que use el nuevo BIGDECIMAL_CAST
  Qbxml::Types::TYPE_MAP["QUANTYPE"] = Qbxml::Types::BIGDECIMAL_CAST
end
