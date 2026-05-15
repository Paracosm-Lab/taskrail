class AddAdapterConfigToStageConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :stage_configs, :adapter_config, :jsonb, null: false, default: {}
  end
end
