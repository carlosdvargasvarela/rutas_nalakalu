require "test_helper"

class ServiceTypeWordTest < ActiveSupport::TestCase
  test "requires a key and a label" do
    word = ServiceTypeWord.new(prefix: "Foo - ")
    assert_not word.valid?
    assert_includes word.errors.attribute_names, :key
    assert_includes word.errors.attribute_names, :label
  end

  test "key must be unique" do
    ServiceTypeWord.create!(key: "recoleccion", label: "Recolección")
    dup = ServiceTypeWord.new(key: "recoleccion", label: "Otra etiqueta")

    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :key
  end
end
