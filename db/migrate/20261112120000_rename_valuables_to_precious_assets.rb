class RenameValuablesToPreciousAssets < ActiveRecord::Migration[8.1]
  CONSTRAINTS = %w[
    bullion_purity_present
    item_type
    purity
    weight_unit
    material_matches_item_type
    weight_unit_matches_item_type
    gemstone_purity_absent
    quantity_positive
  ].freeze
  LEGACY_CONSTRAINTS = %w[
    description_present
    cost
    making_charge
    manual_value
    positive_weight
  ].freeze

  def up
    rename_table :valuables, :precious_assets
    rename_table :valuable_items, :precious_asset_items
    rename_column :precious_asset_items, :valuable_id, :precious_asset_id
    rename_constraints(from: "valuable_items", to: "precious_asset_items")
    rename_constraints(from: "precious_metal_lots", to: "precious_asset_items", names: LEGACY_CONSTRAINTS)

    rename_stored_types(from: "Valuable", to: "PreciousAsset", item_from: "ValuableItem", item_to: "PreciousAssetItem")
  end

  def down
    rename_stored_types(from: "PreciousAsset", to: "Valuable", item_from: "PreciousAssetItem", item_to: "ValuableItem")

    rename_constraints(from: "precious_asset_items", to: "precious_metal_lots", names: LEGACY_CONSTRAINTS)
    rename_constraints(from: "precious_asset_items", to: "valuable_items")
    rename_column :precious_asset_items, :precious_asset_id, :valuable_id
    rename_table :precious_asset_items, :valuable_items
    rename_table :precious_assets, :valuables
  end

  private
    def rename_constraints(from:, to:, names: CONSTRAINTS)
      table = connection.data_source_exists?("precious_asset_items") ? "precious_asset_items" : "valuable_items"
      names.each do |name|
        execute "ALTER TABLE #{quote_table_name(table)} RENAME CONSTRAINT #{quote_column_name("#{from}_#{name}")} TO #{quote_column_name("#{to}_#{name}")}"
      end
    end

    def rename_stored_types(from:, to:, item_from:, item_to:)
      %w[accounts financekit_accounts].each do |table|
        next unless connection.column_exists?(table, :accountable_type)

        execute "UPDATE #{quote_table_name(table)} SET accountable_type = #{quote(to)} WHERE accountable_type = #{quote(from)}"
      end
      execute "UPDATE active_storage_attachments SET record_type = #{quote(item_to)} WHERE record_type = #{quote(item_from)}"
      replace_import_mapping_type(item_to, from: item_from)
    end

    # The allowed types are read from the current constraint, so types added
    # since it was written are kept.
    def replace_import_mapping_type(type, from:)
      %w[source_type target_type].each do |column|
        name = "chk_import_source_mappings_#{column}"
        definition = connection.select_value(<<~SQL.squish)
          SELECT pg_get_constraintdef(oid) FROM pg_constraint
          WHERE conname = #{quote(name)} AND conrelid = 'import_source_mappings'::regclass
        SQL
        next unless definition&.include?("'#{from}'")

        remove_check_constraint :import_source_mappings, name: name
        execute "UPDATE import_source_mappings SET #{column} = #{quote(type)} WHERE #{column} = #{quote(from)}"
        expression = definition.delete_prefix("CHECK (").delete_suffix(")").gsub("'#{from}'", "'#{type}'")
        add_check_constraint :import_source_mappings, expression, name: name
      end
    end

    def quote(value)
      connection.quote(value)
    end
end
