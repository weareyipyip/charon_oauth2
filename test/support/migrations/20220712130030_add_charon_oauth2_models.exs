defmodule CharonOauth2.Test.Repo.Migrations.AddCharonOauth2Models do
  use Ecto.Migration

  def change do
    create table("users") do
    end

    create table("charon_oauth2_clients", primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :text, null: false)
      add(:secret, :text, null: false)
      add(:redirect_uris, {:array, :text}, null: false)
      add(:scopes, {:array, :text}, null: false)
      add(:grant_types, {:array, :text}, null: false)
      add(:client_type, :text, null: false)
      add(:owner_id, references("users", on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create table("charon_oauth2_authorizations") do
      add(:client_id, references("charon_oauth2_clients", type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:resource_owner_id, references("users", on_delete: :delete_all), null: false)
      add(:scopes, {:array, :text}, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index("charon_oauth2_authorizations", [:client_id, :resource_owner_id]))
    create(index("charon_oauth2_authorizations", [:resource_owner_id]))

    create table("charon_oauth2_grants") do
      add(:code, :text)
      add(:redirect_uri, :text)
      add(:type, :text, null: false)
      add(:expires_at, :utc_datetime, null: false)

      add(:authorization_id, references("charon_oauth2_authorizations", on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime)
    end

    create(index("charon_oauth2_grants", [:authorization_id]))
    create(unique_index("charon_oauth2_grants", [:code]))
  end
end
