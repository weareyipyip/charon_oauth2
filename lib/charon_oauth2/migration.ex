defmodule CharonOauth2.Migration do
  @moduledoc """
  Helper module for client app migrations.

  ## Usage

      defmodule MyApp.Repo.Migrations.Oauth2Models do
        use Ecto.Migration

        def change, do: CharonOauth2.Migration.change(charon_config)
      end
  """
  import Ecto.Migration

  @doc """
  Call from a migration to generate `CharonOauth2` models. Supports rollbacks as well.
  """
  @spec change(Charon.Config.t()) :: any()
  def change(config) do
    mod_config = CharonOauth2.Internal.get_module_config(config)
    resource_owner_table = mod_config.resource_owner_schema.__schema__(:source)
    resource_owner_id_column = mod_config.resource_owner_id_column
    resource_owner_id_type = mod_config.resource_owner_id_type

    create table(mod_config.client_table, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :text, null: false)
      add(:secret, :binary, null: false)
      add(:redirect_uris, {:array, :text}, null: false)
      add(:scopes, {:array, :text}, null: false)
      add(:grant_types, {:array, :text}, null: false)
      add(:client_type, :text, null: false)
      add(:description, :text)

      add(
        :owner_id,
        references(resource_owner_table,
          on_delete: :delete_all,
          column: resource_owner_id_column,
          type: resource_owner_id_type
        ),
        null: false
      )

      timestamps(type: :utc_datetime)
    end

    create table(mod_config.authorization_table) do
      add(
        :client_id,
        references(mod_config.client_table, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(
        :resource_owner_id,
        references(resource_owner_table,
          on_delete: :delete_all,
          column: resource_owner_id_column,
          type: resource_owner_id_type
        ),
        null: false
      )

      add(:scopes, {:array, :text}, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(mod_config.authorization_table, [:client_id, :resource_owner_id]))
    create(index(mod_config.authorization_table, [:resource_owner_id]))

    create table(mod_config.grant_table) do
      add(:code, :binary)
      add(:redirect_uri, :text)
      add(:type, :text, null: false)
      add(:expires_at, :utc_datetime, null: false)

      add(:authorization_id, references(mod_config.authorization_table, on_delete: :delete_all),
        null: false
      )

      add(
        :resource_owner_id,
        references(resource_owner_table,
          on_delete: :delete_all,
          column: resource_owner_id_column,
          type: resource_owner_id_type
        ),
        null: false
      )

      timestamps(type: :utc_datetime)
    end

    create(index(mod_config.grant_table, [:authorization_id]))
    create(index(mod_config.grant_table, [:resource_owner_id]))
    create(unique_index(mod_config.grant_table, [:code]))
  end
end
