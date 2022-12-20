defmodule CharonOauth2.Migration do
  @moduledoc """
  Helper module for client app migrations.

  ## Usage

      defmodule MyApp.Repo.Migrations.Oauth2Models do
        use Ecto.Migration

        def change, do: CharonOauth2.Migration.change("users")
      end
  """
  import Ecto.Migration

  @type change_opts :: [
          client_table: String.t(),
          authorization_table: String.t(),
          grant_table: String.t()
        ]

  @doc """
  Call from a migration to generate `CharonOauth2` models. Supports rollbacks as well.
  """
  @spec change(String.t(), change_opts()) :: any()
  def change(user_table, opts \\ []) do
    client_table = opts[:client_table] || "charon_oauth2_clients"
    authorization_table = opts[:authorization_table] || "charon_oauth2_authorizations"
    grant_table = opts[:grant_table] || "charon_oauth2_grants"

    create table(client_table, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :text, null: false)
      add(:secret, :text, null: false)
      add(:redirect_uris, {:array, :text}, null: false)
      add(:scopes, {:array, :text}, null: false)
      add(:grant_types, {:array, :text}, null: false)
      add(:client_type, :text, null: false)
      add(:owner_id, references(user_table, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create table(authorization_table) do
      add(:client_id, references(client_table, type: :uuid, on_delete: :delete_all), null: false)
      add(:resource_owner_id, references(user_table, on_delete: :delete_all), null: false)
      add(:scopes, {:array, :text}, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(authorization_table, [:client_id, :resource_owner_id]))
    create(index(authorization_table, [:resource_owner_id]))

    create table(grant_table) do
      add(:code, :text)
      add(:redirect_uri, :text)
      add(:type, :text, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:authorization_id, references(authorization_table, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(grant_table, [:authorization_id]))
    create(unique_index(grant_table, [:code]))
  end
end
