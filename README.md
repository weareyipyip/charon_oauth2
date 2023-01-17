# CharonOauth2

CharonOauth2 is a child package of [Charon](https://github.com/weareyipyip/charon) that adds Oauth2 authorization server capability to a Charon-powered application. CharonOauth2 implements recommendations from the [Oauth 2.1 draft spec](https://www.ietf.org/archive/id/draft-ietf-oauth-v2-1-07.html), such as enforcing PKCE with the authorization code grant for all clients.

Charon is an auth framework for Elixir aimed at APIs. As such, CharonOauth2 does not include an "authorize app X to use your Y account" page. Such a page is necessary for Oauth2, and adding it is left to the client application using whatever stack it chooses. CharonOauth does include an endpoint plug that does almost all of the heavy lifting of such a page, so that CharonOauth2 can be easily used without having to dive into the Oauth2 spec.

## Table of contents

<!-- TOC -->

- [Charon](#Charon)
  - [Table of contents](#table-of-contents)
  - [Features](#features)
  - [Documentation](#documentation)
  - [How to use](#how-to-use)
    - [Installation](#installation)
    - [Set up Charon](#set-up-charon)
    - [Configuration](#configuration)
    - [Migrations](#migrations)
    - [Create your CharonOauth2 module](#create-your-charonoauth2-module)
    - [Add routes and controllers](#add-routes-and-controllers)
    - [Restrict third-party application access using scopes](#restrict-third-party-application-access-using-scopes)
    - [Add an authorization page](#add-an-authorization-page)

<!-- /TOC -->

## Features

- Oauth 2.1 authorization server implementation supporting authorization_code and refresh_token grants.
- Out-of-the-box database migrations, models, and contexts.
- Simple configuration with sane defaults.
- Revokable refresh tokens thanks to Charon's session store.
- Symmetric or asymmetric token signatures thanks to Charon's token factory.
- Safe storage of sensitive data using encryption (`CharonOauth2.Types.Encrypted`) or HMAC (`CharonOauth2.Types.Hmac`) when appropriate.
- Small number of dependencies.

## Documentation

Documentation can be found at [https://hexdocs.pm/charon_oauth2](https://hexdocs.pm/charon_oauth2).

## How to use

### Installation

The package can be installed by adding `charon_oauth2` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:charon, "~> 2.0"},
    {:charon_oauth2, "~> 0.0.0+development"}
  ]
end
```

### Set up Charon

Set up [Charon](https://github.com/weareyipyip/charon) first using its readme.

### Configuration

Configuration is easy. You simply add the `CharonOauth2` configuration as optional module configuration for Charon.
Add your repo, resource owner (user) schema, and scopes. We will discuss scopes in more detail [later](#restrict-third-party-application-access-using-scopes). For now, you can add an empty list.

```elixir
Charon.Config.from_enum(
  ...,
  optional_modules: %{
    CharonOauth2 => %{
      repo: MyApp.Repo,
      resource_owner_schema: MyApp.User,
      scopes: []
    }
  }
)
```

For all config options, take a look at `CharonOauth2.Config`.

### Migrations

To create the required database tables, you can use the included migration helper `CharonOauth2.Migration`.

```bash
mix ecto.gen.migration charon_oauth2_models
```

```elixir
defmodule MyApp.Repo.Migrations.CharonOauth2Models do
  use Ecto.Migration

  @my_charon_config MyApp.Charon.get_config()

  def change, do: CharonOauth2.Migration.change(@my_charon_config)
end
```

### Create your CharonOauth2 module

To provide you with models, contexts and plugs, CharonOauth2 generates several modules for you.
Create a CharonOauth2 module, simply passing in the Charon config:

```elixir
defmodule MyApp.CharonOauth2 do
  use CharonOauth2, MyApp.Charon.get_config()
end
```

Now you will have the following additional modules:

- `MyApp.CharonOauth2.Authorization`
- `MyApp.CharonOauth2.Authorizations`
- `MyApp.CharonOauth2.Client`
- `MyApp.CharonOauth2.Clients`
- `MyApp.CharonOauth2.Grant`
- `MyApp.CharonOauth2.Grants`
- `MyApp.CharonOauth2.Plugs.AuthorizationEndpoint`
- `MyApp.CharonOauth2.Plugs.TokenEndpoint`

Now you only have to update your user schema:

```elixir
defmodule MyApp.User do
  use Ecto.Schema

  alias MyApp.CharonOauth2.{Authorization, Client}

  schema "users" do
    ...

    has_many :oauth2_authorizations, Authorization, foreign_key: :resource_owner_id
    has_many :oauth2_clients, Client, foreign_key: :owner_id
  end
end
```

### Add Oauth2 routes

Oauth2 requires to important endpoints, the authorization endpoint and the token endpoint.
You can add both by forwarding to the two "endpoint plugs":

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  alias MyApp.CharonOauth2.Plugs.{AuthorizationEndpoint, TokenEndpoint}
  import Charon.TokenPlugs

  @my_charon_config MyApp.Charon.get_config()

  ...

  pipeline :authorize_oauth2 do
    # conveniently, the scope claim is an ordset by default - make sure it stays that way
    plug :verify_token_ordset_claim_contains, {"scope", :ordsets.from_list(~w(authorization:write grant:write))}
    plug :verify_no_auth_error, &MyAppWeb.charon_error_handler/2
  end

  scope "/api" do
    pipe_through [:api ,:valid_access_token, :authorize_oauth2]

    # auth endpoint MUST only be accessible by Charon-authenticated users
    # AND only by privileged, first-party applications
    # that have access to scopes authorization:write and grant:write (or similar)
    forward "/oauth2/authorize", AuthorizationEndpoint, config: @my_charon_config
  end

  scope "/api" do
    # token endpoint does its own parsing and requires no authentication
    forward "/oauth2/token", TokenEndpoint, config: @my_charon_config
  end

```

### Add an authorization page

### Restrict third-party application access using scopes

### Most importantly
