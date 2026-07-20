class ReplaceOrderItemNotesWithDeliveryItemNotes < ActiveRecord::Migration[7.2]
  # "Notas de producción" pasan de colgar del order_item a colgar del delivery_item,
  # para que un caso de servicio (retiro/devolución/reparación) que comparte order_item
  # con la entrega original tenga su propio hilo de notas.
  def up
    create_table :delivery_item_notes do |t|
      t.integer :delivery_item_id, null: false
      t.integer :user_id, null: false
      t.text :body, null: false
      t.boolean :closed, default: false, null: false
      t.timestamps
    end
    add_index :delivery_item_notes, :delivery_item_id
    add_index :delivery_item_notes, :user_id
    add_foreign_key :delivery_item_notes, :delivery_items
    add_foreign_key :delivery_item_notes, :users

    # Cada nota existente se asigna al delivery_item más antiguo de su order_item
    # (la entrega original, ya que las entregas de servicio se crean después).
    # NOT EXISTS en vez de DISTINCT ON para que funcione igual en sqlite (dev/test)
    # y postgres (producción).
    before_count = select_value("SELECT COUNT(*) FROM order_item_notes").to_i

    execute <<-SQL
      INSERT INTO delivery_item_notes (delivery_item_id, user_id, body, closed, created_at, updated_at)
      SELECT earliest.id, oin.user_id, oin.body, oin.closed, oin.created_at, oin.updated_at
      FROM order_item_notes oin
      JOIN delivery_items earliest ON earliest.order_item_id = oin.order_item_id
      WHERE NOT EXISTS (
        SELECT 1 FROM delivery_items other
        WHERE other.order_item_id = earliest.order_item_id
        AND (other.created_at < earliest.created_at
             OR (other.created_at = earliest.created_at AND other.id < earliest.id))
      )
    SQL

    after_count = select_value("SELECT COUNT(*) FROM delivery_item_notes").to_i
    if after_count < before_count
      raise ActiveRecord::IrreversibleMigration,
        "#{before_count - after_count} order_item_notes no se pudieron migrar " \
        "(su order_item no tiene ningún delivery_item). Revisar antes de continuar."
    end

    drop_table :order_item_notes
  end

  def down
    create_table :order_item_notes do |t|
      t.integer :order_item_id, null: false
      t.integer :user_id, null: false
      t.text :body, null: false
      t.boolean :closed, default: false, null: false
      t.timestamps
    end
    add_index :order_item_notes, :order_item_id
    add_index :order_item_notes, :user_id
    add_foreign_key :order_item_notes, :order_items
    add_foreign_key :order_item_notes, :users

    execute <<-SQL
      INSERT INTO order_item_notes (order_item_id, user_id, body, closed, created_at, updated_at)
      SELECT di.order_item_id, din.user_id, din.body, din.closed, din.created_at, din.updated_at
      FROM delivery_item_notes din
      JOIN delivery_items di ON di.id = din.delivery_item_id
    SQL

    drop_table :delivery_item_notes
  end
end
