# CharonOauth2

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `charon_oauth2` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:charon_oauth2, "~> 0.0.0+development"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/charon_oauth2>.

## Migrations

You must create appropriate models f

```bash
mix ecto.gen.migration oauth2_models
```

```elixir
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
```

## Config

Package uses session store, to prevent delete_all from throwing away oauth2 sessions, use separate config for charonoauth2.

## Models

Defining Ecto models is left to the application as well.
Notably, creating and managing `oauth2_clients` is not handled by the dependency at all.
