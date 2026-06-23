class CreateServiceTypeWordsAndDetectorKeywordLists < ActiveRecord::Migration[7.2]
  def change
    create_table :service_type_words do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.string :prefix, default: "", null: false
      t.timestamps
    end
    add_index :service_type_words, :key, unique: true

    create_table :detector_keyword_lists do |t|
      t.string :detector, null: false
      t.string :list_name, null: false
      t.text :values_list, default: "[]", null: false
      t.timestamps
    end
    add_index :detector_keyword_lists, [:detector, :list_name], unique: true, name: "index_detector_keyword_lists_on_detector_and_list_name"
  end
end
