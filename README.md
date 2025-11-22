# CharonOauth2

CharonOauth2 is a child package of [Charon](https://github.com/weareyipyip/charon) that adds OAuth2 authorization server capability to a Charon-secured application. Charon is an authentication framework for Elixir aimed primarily at securing APIs.

**Key characteristics:**

- **Integrates with your existing app**: Not a standalone service - CharonOauth2 is a library that you add to _your_ Elixir/Phoenix app to add OAuth2 authorization server capabilities to it. Your user accounts and authentication remain centralized.
- **Combined authorization and resource server**: Your application becomes both the OAuth2 authorization server (issues tokens) and resource server (protects API resources). This is a common and recommended pattern - just design your scopes carefully to control third-party access.
- **Bring your own UI**: CharonOauth2 does not include a pre-built authorization consent page. You implement this using your preferred frontend stack, while CharonOauth2 provides endpoint plugs that handle all the OAuth2 protocol complexity.
- **OAuth 2.1 compliant**: Implements recommendations from the [OAuth 2.1 draft spec](https://www.ietf.org/archive/id/draft-ietf-oauth-v2-1-07.html), including mandatory PKCE for all authorization code flows.

## Table of contents

- [Features](#features)
- [Documentation](#documentation)
- [How to use](#how-to-use)
  - [Installation](#installation)
  - [Set up Charon](#set-up-charon)
  - [Configuration](#configuration)
  - [Migrations](#migrations)
  - [Create your CharonOauth2 module](#create-your-charonoauth2-module)
  - [Add OAuth2 routes](#add-oauth2-routes)
  - [Add an authorization page](#add-an-authorization-page)
    - [Implementation flow and React example](#implementation-flow-and-react-example)
    - [Add API endpoints needed for authorization page](#add-api-endpoints-needed-for-authorization-page)
  - [Restrict third-party application access using scopes](#restrict-third-party-application-access-using-scopes)
    - [What are scopes?](#what-are-scopes)
    - [Designing scopes](#designing-scopes)
    - [Recommendations](#recommendations)
    - [Example: Building access app scopes](#example-building-access-app-scopes)
    - [Enforcing scopes](#enforcing-scopes)
    - [Separating first-party and third-party clients](#separating-first-party-and-third-party-clients)
  - [Managing authorizations and clients](#managing-authorizations-and-clients)
  - [Testing](#testing)

## Features

- **OAuth 2.1 authorization server**: Supports `authorization_code` (with mandatory PKCE), `client_credentials` and `refresh_token` flows
- **Database ready**: Out-of-the-box Ecto migrations, schemas, and contexts for clients, grants, and authorizations
- **Simple configuration**: Minimal setup with sensible defaults - configure repo, user schema, and scopes, and you're ready
- **Revocable refresh tokens**: Built on Charon's session store for secure token lifecycle management
- **Flexible token signing**: Supports symmetric (HMAC-SHA256), Poly1305, and asymmetric (EdDSA with Ed25519/Ed448) signatures via Charon's JWT token factory
- **Secure data storage**: Sensitive data like client secrets is securely stored encrypted or HMAC'ed.
- **Lightweight**: Minimal dependency footprint; you only need `Plug`, `Ecto` and `Charon`.

## Documentation

Documentation can be found at [https://hexdocs.pm/charon_oauth2](https://hexdocs.pm/charon_oauth2).

## Installation

The package can be installed by adding `charon_oauth2` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:charon, "~> 4.0"},
    {:charon_oauth2, "~> 1.0"}
  ]
end
```

## Set up Charon

Set up [Charon](https://hexdocs.pm/charon) first using its readme. The examples below assume you have already set up Charon and have working authentication. CharonOauth2 builds on top of Charon's authentication infrastructure.

## Configuration

CharonOauth2 configuration is added as an optional module in your Charon config. At minimum, you need to specify:

- `repo`: Your Ecto repo module
- `resource_owner_schema`: Your user schema module
- `scopes`: List of OAuth2 scopes (we'll discuss these [later](#restrict-third-party-application-access-using-scopes))

You may also want to restrict the flow you wish to support with option `grant_types`, notably by excluding `client_credentials`.

```elixir
# In your Charon configuration module
defmodule MyApp.Charon do
  @config Charon.Config.from_enum(
    # ...
    # charon config here
    # ...
    optional_modules: %{
      CharonOauth2 => %{
        repo: MyApp.Repo,
        resource_owner_schema: MyApp.User,
        grant_types: ~w(authorization_code refresh_token),
        scopes: ["posts:read", "posts:write"] # more on scopes to follow
      }
    }
  )

  def get_config, do: @config
end
```

For all available configuration options, see `CharonOauth2.Config`.

## Migrations

To create the required database tables, you can use the included migration helper `CharonOauth2.Migration`.

```bash
mix ecto.gen.migration charon_oauth2_models
```

```elixir
defmodule MyApp.Repo.Migrations.CharonOauth2Models do
  use Ecto.Migration

  @charon_conf MyApp.Charon.get_config()

  def change, do: CharonOauth2.Migration.change(@charon_conf)
end
```

## Create your CharonOauth2 module

To provide you with models, contexts and plugs, CharonOauth2 generates several modules for you.
To create a CharonOauth2 module, simply pass in the Charon config:

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
- `MyApp.CharonOauth2.TestSeeds`

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

## Add OAuth2 routes

OAuth2 requires two standard endpoints:

1. **Authorization endpoint** (`/api/oauth2/authorize`): Where users grant permission to clients. Must be protected - only authenticated users can access it.
2. **Token endpoint** (`/api/oauth2/token`): Where clients exchange authorization codes for access tokens. Public endpoint with no (user) authentication required (confidential clients do authenticate but that is handled by the TokenEndpoint plug itself).

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  alias MyApp.CharonOauth2.Plugs.{AuthorizationEndpoint, TokenEndpoint}

  @charon_conf MyApp.Charon.get_config()

  scope "/api" do
    pipe_through :api

    # Token endpoint - public, no authentication pipeline needed
    # Clients exchange authorization codes for tokens here
    forward "/oauth2/token", TokenEndpoint, config: @charon_conf

    scope "/" do
      pipe_through :authenticated  # Use your Charon authentication pipeline

      # Authorization endpoint - requires authentication
      # Users authorize OAuth2 clients here (that's why they must be logged in)
      forward "/oauth2/authorize", AuthorizationEndpoint, config: @charon_conf
    end

  end
end
```

## Add an authorization page

The authorization page is where users grant or deny permission for OAuth2 clients (third-party apps) to access their account. The `MyApp.CharonOauth2.Plugs.AuthorizationEndpoint` handles all OAuth2 protocol validation, so your frontend implementation focuses on the user experience. This is an example page as a React SPA. If you use a Phoenix HTML page, you will not need the endpoints and can just pass the data to the page as usual.

### Implementation flow and React example

This **[React example](./example-auth-page.md)** implements the following flow:

1. Verify that query param `client_id` is present (other parameters are verified by the authorization endpoint).

1. Verify that the user is logged in, and redirect to the login page if they are not.

1. You now need to fetch data; you can do these three API calls in parallel:

   - Fetch existing authorization to check if - and to what extent - the user has previously authorized this client (`GET /api/my/oauth2_authorizations/:client_id`).

   - Fetch client details like name and description to show the user which app they are authorizing (`GET /api/oauth2_clients/:client_id`).

   - Fetch available scopes with their descriptions to explain to the user which permissions they are granting (`GET /api/scopes`).

1. Determine requested scopes:

   - If `scope` query param exists, use that (split on whitespace)
   - Otherwise, use the client's default configured scopes

1. Compare scopes: Check if any requested scopes haven't been authorized yet

1. Show authorization UI (if needed): If there are new scopes (or if the client has not been authorized yet), display them and ask for permission

1. Submit to authorization endpoint: POST all original query parameters plus `permission_granted: true/false` to the authorization endpoint.

   ```jsonc
   // POST /api/oauth2/authorize
   {
     "client_id": "...",
     "redirect_uri": "...",
     "response_type": "code",
     "scope": "profile:read posts:write",
     "state": "...",
     "code_challenge": "...",
     "code_challenge_method": "S256",
     "permission_granted": true
   }
   ```

1. Handle response:
   - 200 OK with `redirect_to`: Redirect user to the provided URL (takes them back to the client app)
   - 400 Bad Request with `errors`: Display error message and **do not redirect** (indicates invalid request params, such as mismatched `redirect_uri`)

### Add API endpoints needed for authorization page

Your application needs to expose these endpoints (or equivalent GraphQL queries) for the authorization page:

1. Get all scopes (public)

   Returns all defined OAuth2 scopes with descriptions:

   ```jsonc
   // GET /api/scopes
   {
     "profile:read": "View your profile details like name and email",
     "posts:write": "Create and edit posts on your behalf",
     "posts:read": "View your posts"
   }
   ```

2. Get OAuth2 client by ID (public)

   Returns client information. You can use `MyApp.CharonOauth2.Clients.get_by/2` to implement this. ⚠️ **Important**: Never expose the `client_secret` field!

   ```jsonc
   // GET /api/oauth2_clients/:id
   {
     "id": "client-123",
     "name": "Todo App",
     "description": "A simple todo application",
     "redirect_uris": ["https://todoapp.example.com/oauth/callback"],
     "scope": "profile:read posts:read"
   }
   ```

3. Get user's authorization for client (authenticated). You can use `MyApp.CharonOauth2.Authorizations.get_by/2` to implement this.

   Returns the current user's existing authorization for this client:

   ```jsonc
   // GET /api/my/oauth2_authorizations/:client_id
   {
     "id": "auth-456",
     "client_id": "client-123",
     "scope": ["profile:read"],
     "inserted_at": "2025-01-15T10:30:00Z"
   }
   ```

## Restrict third-party application access using scopes

At this point, CharonOauth2 is fully integrated into your application as an OAuth2 authorization server. However, there's one critical task remaining: **designing and enforcing scopes** to control what third-party applications can do on behalf of your users.

This is the resource server side of OAuth2, and it cannot be abstracted into a library because it's deeply tied to your application's specific API structure and business logic.

### What are scopes?

Scopes are a misunderstood concept. Scopes represent _application_ permissions, not _user_ permissions. This is a crucial distinction:

- **User permissions (roles, ACLs)**: What the _user_ is allowed to do
- **Application permissions (scopes)**: What the _application_ is allowed to do

If an application acts on behalf of a user, both must be satisfied for an operation to succeed. This is usually the case, only when using the `client_credentials` grant is an application acting on its own behalf, in which case only application permissions (scopes) apply. But that is an advanced use case that you should avoid unless you have a very good reason to use it - it is meant for machine-to-machine auth only.

### Example: Building door access

Imagine your app can unlock building doors:

- User permission: Alice belongs to Building A, so she can unlock its doors
- Application permission: A third-party app needs scope `door:open` to unlock doors on Alice's behalf

Even though Alice has permission to open the door, a third-party app can only do so if Alice has granted it the `door:open` scope. This is why scopes cannot replace user permissions, and user permissions cannot replace scopes.

### Designing scopes

Scope design isn't always straightforward. Consider:

- Are scopes hierarchical? Does `door:open` imply `door:read`?

  - If `POST /doors/:id/open` returns 204 No Content, maybe not
  - If it returns door configuration data, then yes
  - Recommendation: Avoid hierarchical scopes - require multiple scopes explicitly when needed

- Do scopes affect other users? Be cautious with endpoints that expose data about other users
  - Example: `GET /my/building/residents` returns names of other residents
  - Those other users haven't consented to share their data with the third-party app
  - Recommendation: Either restrict such endpoints from third-party access entirely, or implement a more granular permission systems

Key principle: Design your scopes thoughtfully. They're your primary defense against third-party apps accessing more than they should.

### Recommendations

**Operations to restrict from third-party applications:**

To prevent privilege escalation and security issues, third-party applications should typically **never** be able to:

- ❌ Read, create, or update OAuth2 grants, authorizations, or clients
- ❌ Update user login credentials (passwords, MFA methods)
- ❌ Read, create, or update push notification tokens
- ❌ Manage user sessions (non-OAuth2 sessions)
- ❌ Access highly privileged accounts (e.g., admin accounts)
- ❌ Read other users' private profile information
- ❌ Refresh tokens using your regular Charon session controller

⚠️ **This is especially critical when running a combined authorization and resource server** (the typical CharonOauth2 setup).

✅ **Enforce these restrictions using scopes** - design your scope system so first-party applications have access to privileged scopes that third-party applications don't.

### Example: Building access app scopes

Here's a practical (non-exhaustive) example of scope design for a building access management application. The scopes are split into two groups - one for all apps including third-party (OAuth2) apps, and one reserved for first-party apps.

```elixir
# Scopes available to all applications (first-party and third-party)
@all_apps_scopes %{
  "profile:read" => "View your profile information",
  "buildings:read" => "View buildings you have access to",
  "apartments:read" => "View apartment details in your buildings",
  "doors:read" => "View door information and access logs",
  "doors:open" => "Unlock doors you have access to"
}

# Privileged scopes - first-party applications only
@first_party_only_scopes %{
  "profile:write" => "Update your profile information",
  "buildings:write" => "Create and manage buildings",
  "apartments:write" => "Create and manage apartments",
  "credentials:write" => "Manage your own credentials like your password",
  "authorizations:read" => "View third-party apps that you've authorized to act on your behalf",
  "authorizations:write" => "Grant and revoke permission for third-party apps to act on your behalf"
}
```

Notice how:

- Read and write operations are separated
- Physical access operations (`doors:open`) are distinct from data access (`doors:read`)
- Administrative operations are isolated in `@first_party_only_scopes`
- Third-party apps can read user data and perform actions on the user's behalf, but cannot manage the system itself

### Enforcing scopes

Scopes need to be enforced in two ways: clients should only have access to scopes that they are allowed to use, and endpoints / pages should enforce that they can only be accessed with the correct scopes.

#### Restricting (third-party) clients

The only scopes that are available to OAuth2 clients are the ones passed to `CharonOauth2.Config` as the `:scopes` parameter. Be aware that restricting these scopes at a later moment may break existing clients. Users can restrict clients (apps) further by only authorizing a subset of these scopes.

#### Verifying scopes in tokens

To enforce that scope(s) are required to access some endpoint, use `Charon.TokenPlugs`. You can do so in your router pipelines, of course, but it may make more sense to enforce scopes as Phoenix [controller plugs](https://hexdocs.pm/phoenix/Phoenix.Controller.html#module-plug-pipeline), so that you don't need to add a pipeline for every scope in your router.

Use Charon's `Charon.TokenPlugs.OrdsetClaimHas` plug to check for required scopes (`CharonOauth2` guarantees that the scope claim is an ordset):

```elixir
# In your controller
defmodule MyAppWeb.PostController do
  use MyAppWeb, :controller

  import Charon.TokenPlugs
  alias Charon.TokenPlugs.OrdsetClaimHas

  plug OrdsetClaimHas, scope: "posts:write" when action in [:create, :update]
  plug OrdsetClaimHas, scope: "posts:read" when action in [:index]
  plug :verify_no_auth_error, &MyAppWeb.ErrorHelpers.handle_auth_error/2

  def create(conn, params) do
    ...
end
```

#### Protecting the authorization endpoint

```elixir
pipeline :require_privileged_scopes do
  plug OrdsetClaimHas, scope: ~w(authorizations:write grants:write)
  plug :verify_no_auth_error, &MyAppWeb.ErrorHelpers.handle_auth_error/2
end

scope "/api" do
  pipe_through [:api, :authenticated, :require_privileged_scopes]
  forward "/oauth2/authorize", AuthorizationEndpoint, config: @charon_conf
end
```

See [Charon's documentation](https://hexdocs.pm/charon/readme.html#protecting-routes) for details on token verification plugs.

### Separating first-party and third-party clients

You have two approaches:

**Option 1: Use existing Charon session controller (recommended)**

Use your regular Charon session controller for first-party applications and grant all scopes to tokens it issues.
Simply pass the privileged scopes (it **must** be an ordset!) to `Charon.SessionPlugs.upsert_session/3` using the `:access_claim_overrides` option.

This keeps session management simple and gives first-party apps full access. See [Charon's session documentation](https://hexdocs.pm/charon/Charon.SessionPlugs.html#upsert_session/3) for details.

**Option 2: Full OAuth2 for everything**

Register your first-party application as an OAuth2 client with privileged scopes using `MyApp.CharonOauth2.Clients.insert/1`.
Then, pre-authorize it for all users (e.g. during registration) using `MyApp.CharonOauth2.Authorizations.insert/1`.
This is more complex but provides a unified authentication flow.

**Recommendation**: Use Option 1 for simplicity unless you have specific requirements for treating all clients uniformly.

## Managing authorizations and clients

You probably need to add the ability for users to manage their authorizations or to register their own OAuth2 clients (be the owner of a third-party app). Operations you probably want to support are:

**All users: manage apps and their access (authorizations)**

- View which apps have access to their account
- Review what permissions (scopes) each app has
- Revoke access for specific apps

**Developers: manage own apps (clients)**

- Register new OAuth2 clients
- List their registered clients
- Update client redirect URIs and scopes
- Delete/deactivate clients
- Regenerate client secrets

The generated context modules (`MyApp.CharonOauth2.Authorizations`, `MyApp.CharonOauth2.Clients` and `MyApp.CharonOauth2.Grants`) provide standard functions for CRUD ops on all OAuth2 resources.

## Testing

If you wish to write tests that involve CharonOauth2 models, you can use the utility functions in
`MyApp.CharonOauth2.TestSeeds` to insert test seeds.

## Copyright and License

Copyright (c) 2025, YipYip B.V.

Charon source code is licensed under the [Apache-2.0 License](./LICENSE.md)
