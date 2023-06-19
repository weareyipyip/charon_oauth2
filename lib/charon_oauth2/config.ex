defmodule CharonOauth2.Config do
  @moduledoc """
  Config module for `CharonOauth2`.

  Unlike `Charon` itself, not all config is runtime config.
  That means overriding some configuration options at runtime may not result in the expected behaviour.
  The reason for this is that several configuration values are read at compile time in order to generate code using macros.
  These config options are also read by the migration helper `CharonOauth2.Migration`,
  and you should generally not change them after initializing CharonOauth2.
  The glossary below specifies which config options are affected.

      Charon.Config.from_enum(
        ...,
        optional_modules: %{
          CharonOauth2 => %{
            repo: MyApp.Repo,
            resource_owner_schema: MyApp.User,
            scopes: ~w(profile:read door:open),
            # following are defaults
            authorizations_table: "charon_oauth2_authorizations",
            clients_table: "charon_oauth2_clients",
            customize_session_upsert_args: &Function.identity/1,
            enforce_pkce: :all,
            grants_table: "charon_oauth2_grants",
            grant_ttl: 10 * 60,
            resource_owner_id_column: :id,
            resource_owner_id_type: :bigserial,
            verify_refresh_token: &CharonOauth2.verify_refresh_token/2,
            seeder_overrides: %{client: %{}, authorization: %{}, grant: %{}}
          }
        }
      )

  ## Glossary

   - `:authorizations_table` (compile-time) the name of the table in which to store authorizations.
   - `:clients_table` (compile-time) the name of the table in which to store clients.
   - `:customize_session_upsert_args` a function that you can use to customize the arguments that are passed by your `MyApp.TokenEndpoint` to `Charon.SessionPlugs.upsert_session/3`. Be careful, usually you might want to add to these arguments, but not override them.
   - `:enforce_pkce` for `:public`, `:all` or `:no` clients
   - `:grant_ttl` time in seconds that a grant (mostly authorization code) takes to expire
   - `:grants_table` (compile-time) the name of the table in which to store grants
   - `:repo` (required, compile-time) the Ecto repo module of your application.
   - `:resource_owner_id_column` (compile-time) the column name, as an atom, of the resource owner's schema's primary key
   - `:resource_owner_id_type` (compile-time) the type, as an atom, of the resource owner's schema's primary key
   - `:resource_owner_schema` (required, compile-time) the user schema module of your application.
   - `:resource_owner_table` (compile-time) the name of the table in resource owners are stored. Taken from `:resource_owner_schema` unless set.
   - `:scopes` (required, compile time) the scopes that are available to Oauth2 apps, application-wide.
   - `:verify_refresh_token` a function that you can use to verify an Oauth2 refresh token for the refresh token grant.
  - `:seeder_overrides` the default values for test models used in `CharonOauth2.Seeders`.

  """
  @enforce_keys [:scopes, :repo, :resource_owner_schema]
  defstruct [
    :repo,
    :resource_owner_schema,
    :scopes,
    authorizations_table: "charon_oauth2_authorizations",
    clients_table: "charon_oauth2_clients",
    customize_session_upsert_args: &Function.identity/1,
    enforce_pkce: :all,
    grants_table: "charon_oauth2_grants",
    # ten minutes
    grant_ttl: 10 * 60,
    resource_owner_id_column: :id,
    resource_owner_id_type: :bigserial,
    resource_owner_table: nil,
    verify_refresh_token: &CharonOauth2.verify_refresh_token/2,
    seeder_overrides: %{}
  ]

  @type t :: %__MODULE__{
          authorizations_table: String.t(),
          clients_table: String.t(),
          customize_session_upsert_args: ([...] -> [...]),
          enforce_pkce: :no | :public | :all,
          grant_ttl: pos_integer(),
          grants_table: String.t(),
          repo: module(),
          resource_owner_id_column: atom(),
          resource_owner_id_type: atom(),
          resource_owner_schema: module(),
          resource_owner_table: nil | String.t(),
          scopes: [String.t()],
          verify_refresh_token: (Plug.Conn.t(), Charon.Config.t() -> Plug.Conn.t()),
          seeder_overrides: %{
            optional(:client) => map(),
            optional(:grant) => map(),
            optional(:authorization) => map()
          }
        }

  @doc """
  Build config struct from enumerable (useful for passing in application environment).
  Raises for missing mandatory keys and sets defaults for optional keys.
  """
  @spec from_enum(Enum.t()) :: t()
  def from_enum(enum), do: struct!(__MODULE__, enum)
end
