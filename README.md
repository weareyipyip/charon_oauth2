# CharonOauth2

CharonOauth2 is a child package of [Charon](https://github.com/weareyipyip/charon) that adds Oauth2 authorization server capability to a Charon-secured application. Charon is an auth framework for Elixir aimed primarily at securing APIs. If you simply add CharonOauth2 to an existing application, you will probably end up with an API that is both the Oauth2 authorization server and resource server. That is perfectly fine, just be careful designing and enforcing your scopes.

Because Charon focuses on securing APIs, CharonOauth2 does not include an "authorize app X to use your Y account" page. Such a page is necessary for Oauth2, and adding it is left to the client application using whatever stack it chooses. CharonOauth does include an endpoint plug that does almost all of the heavy lifting of such a page, so that CharonOauth2 can be easily used without having to dive into the Oauth2 spec. This makes CharonOauth2 a little less of a batteries-included solution, but since you probably have a web app already, or a stack preference, or obnoxious developers or whatever, this shouldn't be too much of an issue in practice.

CharonOauth2 implements recommendations from the [Oauth 2.1 draft spec](https://www.ietf.org/archive/id/draft-ietf-oauth-v2-1-07.html), such as enforcing PKCE with the authorization code grant for all clients.

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
    - [Add Oauth2 routes](#add-oauth2-routes)
    - [Add an authorization page](#add-an-authorization-page)
      - [Add API endpoints needed for authorization page](#add-api-endpoints-needed-for-authorization-page)
    - [Restrict third-party application access using scopes](#restrict-third-party-application-access-using-scopes)
      - [What are scopes?](#what-are-scopes)
      - [Enforcing scopes](#enforcing-scopes)
    - [Managing authorizations and clients](#managing-authorizations-and-clients)

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

Oauth2 requires two important endpoints, the authorization endpoint and the token endpoint.
You can add both by forwarding to the two "endpoint plugs":

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  alias MyApp.CharonOauth2.Plugs.{AuthorizationEndpoint, TokenEndpoint}
  import Charon.TokenPlugs

  @my_charon_config MyApp.Charon.get_config()

  ...

  scope "/api" do
    pipe_through [:api ,:valid_access_token]

    # auth endpoint MUST only be accessible by Charon-authenticated users
    forward "/oauth2/authorize", AuthorizationEndpoint, config: @my_charon_config
  end

  scope "/api" do
    # token endpoint does its own request body parsing and requires no authentication
    forward "/oauth2/token", TokenEndpoint, config: @my_charon_config
  end
end
```

### Add an authorization page

The authorization page receives the authorization request from third-party apps (Oauth2 clients). Its purpose is to allow the user to grant or deny permission to access or use (parts of) the user's account. This access is limited by scopes.

`MyApp.CharonOauth2.AuthorizationEndpoint` verifies everything that needs verifying, so your implementation does not necessarily have to concern itself with validating query params. However, to provide a nice UX, it will have to make sure that:

1. `client_id` is present
1. the user is logged-in (redirect to login page otherwise)

The page must do the following:

1. Fetch an existing authorization for the client by the logged-in user from the API.
1. Fetch the client from the API.
1. Fetch all defined scopes with their descriptions from the API.
1. Determine which scopes are requested:
   - IF the `scope` query parameter is set, split it on whitespace " ".
   - OR the fetched client's configured `scope`.
1. Compare the requested scopes to the already-authorized scopes (if any).
1. IF there are yet-to-be-authorized scopes, show them to the user and ask for permission.
1. Call the authorization endpoint with all query params in the request body plus `"permission_granted": <boolean>` (this should be `true` if the user has already granted permission for all requested scopes).
1. Process the response
   - IF 200 OK and `redirect_to`, then redirect to the provided link. This redirect may also contain an error response.
   - IF 400 Bad Request and `errors`, show the user an error message and _don't redirect_ (this basically only happens if something is wrong with request parameters that would make it unsafe to redirect to the client, for example, the `redirect_uri` does not match the one configured for the client).

#### React example

A React example can be found [here](./example-auth-page.md).

#### Add API endpoints needed for authorization page

You will need the following (or similar in GraphQL or something):

- `GET /api/scopes` (public) all defined application scopes, and probably their (default) descriptions, e.g. `{"profile:read": "View your profile details like your name and email."}`.
- `GET /api/oauth2_clients/:id` (public) Oauth2 client by ID. Be careful _not_ to render the client secret here!
- `GET /api/my/oauth2_authorizations/:client_id` (private) current user's existing authorization for the specified client.

Implementations for these endpoints are trivial and are not shown.

### Restrict third-party application access using scopes

You are now basically done as far as adding `CharonOauth2` to your app is concerned. Hurray!
However, you actually still have to do the most difficult part :see_no_evil:,
which is restricting third-party access to your API using scopes
(technically, the part of it that functions as an Oauth2 resource server).
For reasons explained below, this is something that cannot be abstracted away in a library.

#### What are scopes?

Scopes are not the easiest concept to grasp in the first place.
They are best thought of as permissions for applications, as opposed to permissions for users.
For an operation to be authorized, both the application and the user must be authorized to perform it.

For example, let's imagine your app can open a building's door.
A user is authorized to open a door if they belong to the building (user permissions)
However, you don't want just any third-party app to open a door on behalf of your user,
except when the user has explicitly granted permission to that app (application permissions).
That is why you want to restrict open-door capability to apps with scope `door:open`, for example.

_So in an Oauth2-enabled app, user permissions (roles etc) can't replace scopes, and scopes can't replace user permissions._

It is not always straightforward which scopes to define for your app,
nor is it always simple which scopes should be needed for which operations.
Does `door:open` imply `door:read`, in other words, are scopes hierarchical?
If your open-door endpoint returns 204 No Content, maybe requiring `door:read` is not a good fit, after all, what data are you reading?
On the other hand, if the endpoint returns the configuration data of the opened door,
you are effectively reading the door's configuration by opening it, and
requiring `door:read` too seems logical.
So `door:open` does not necessarily imply `door:read` and it really depends on the application.
It's probably best if scopes are not hierarchical and you simply require multiple scopes for the same operation where appropriate,
not in the last place to preserve your own sanity.

Another problem arises if your API returns other users' data.
For example, if your application provides a `GET /my/building/residents` endpoint,
you may run into privacy or even legal issues if you let third-party apps access that
endpoint. Your users may have agreed somewhere that their co-residents can see their names,
and that your application knows who live together in the same building. So without
third-party access, everything is fine.

However, if you then add Oauth2 third-party app access, a user grants permission
to such an app to use their account, and that app can then see other user's names,
a situation has arisen in which those other users have NOT granted any permissions to the third-party app,
but it has some of their data anyway.

So design your API and scopes well.

##### Recommendations

You should probably never allow third-party applications to do the following things, to prevent privilege escalation:

- Read, create or update Oauth2 grants, authorizations or clients.
- Update a user's login credentials like passwords or MFA methods.
- Read, create or update a user's push tokens.
- Read, create or update a user's (non-Oauth2) sessions.
- Access highly privileged accounts like application-wide admin accounts, if you have those.
- Read other users' profiles.
- Refresh tokens using an existing Charon session controller.

It is especially important to be aware of this if your use of CharonOauth2 creates a combined authorization- and resource server.
You can (and should) use scopes to enforce these restrictions.

#### Enforcing scopes

This is the easy part, simply verify the scope claim in a token:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  alias MyApp.CharonOauth2.Plugs.{AuthorizationEndpoint, TokenEndpoint}
  import Charon.TokenPlugs

  @my_charon_config MyApp.Charon.get_config()

  ...

  pipeline :restrict_authorization_access do
    # the scope claim is an ordset (see :ordsets)
    # this enforces that *both* scopes are present in the token claim
    plug :verify_token_ordset_claim_contains, {"scope", :ordsets.from_list(~w(authorization:write grant:write))}
    plug :verify_no_auth_error, &MyAppWeb.charon_error_handler/2
  end

  scope "/api" do
    pipe_through [:api ,:valid_access_token, :restrict_authorization_access]

    # auth endpoint MUST only be accessible by Charon-authenticated users
    # AND only by privileged, first-party applications
    # that have access to scopes authorization:write and grant:write (or similar)
    forward "/oauth2/authorize", AuthorizationEndpoint, config: @my_charon_config
  end

  scope "/api" do
    # token endpoint does its own parsing and requires no authentication
    forward "/oauth2/token", TokenEndpoint, config: @my_charon_config
  end
end
```

You can enforce scopes to separate first-party and third-party clients.

To make sure that first-party clients have scopes that third-party clients don't have,
you can simply use an existing session controller
(for example, the one you created for [Charon](https://github.com/weareyipyip/charon))
and grant all scopes to tokens handed out by it.
This is the easiest and recommended way, because all of the nice things like session management
will stay straightforward.

Alternatively, you can go "full Oauth2", adding your own first-party client as an Oauth2 client that
has access to scopes that other clients don't, and use that for your own applications.
In that case you can throw away your "normal" Charon session controller.
Also, you probably want to "pre-authorize" each user for your own client.

### Managing authorizations and clients

To round off, you may wish to add the ability for users to register their own Oauth2 clients (be the owner of a third-party app) or manage their authorizations. These require simple CRUD operations on `MyApp.CharonOauth2.Clients` and `MyApp.CharonOauth2.Authorizations`, respectively. Implementing controllers or GraphQL resolvers for those operations is entrusted to the reader's capabilities ;)
