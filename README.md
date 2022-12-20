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
defmodule MyApp.Repo.Migrations.Oauth2Models do
  use Ecto.Migration

  def change, do: CharonOauth2.Migration.change("users")
end
```

## Config

Package uses session store, to prevent delete_all from throwing away oauth2 sessions, use separate config for charonoauth2.

## Models

Defining Ecto models is left to the application as well.
Notably, creating and managing `oauth2_clients` is not handled by the dependency at all.
