defmodule CharonOauth2 do
  @moduledoc """
      use CharonOauth2, @charon_config
  """
  alias __MODULE__.Internal

  alias CharonOauth2.Internal.GenMod.{
    Authorization,
    Authorizations,
    Client,
    Clients,
    Grant,
    Grants
  }

  alias CharonOauth2.Internal.GenMod.Plugs.{AuthorizationEndpoint, TokenEndpoint}
  import Charon.TokenPlugs

  @doc false
  def init_config(enum), do: __MODULE__.Config.from_enum(enum)

  @doc """
  Default token verification call used in refresh_token grant.
  Can be overridden using config opt `:verify_refresh_token`,
  in which case there is no need to call `Charon.TokenPlugs.verify_no_auth_error/2`.

  Checks:
   - signature valid
   - already valid ("nbf" claim)
   - not expired ("exp" claim)
   - token type is "refresh" ("type" claim)
   - session type is "oauth2" ("styp" claim)
   - session exists
   - token is fresh (grace period 10 seconds)
  """
  @spec verify_refresh_token(Plug.Conn.t(), Charon.Config.t()) :: Plug.Conn.t()
  def verify_refresh_token(conn, charon_config) do
    conn
    |> verify_token_signature(charon_config)
    |> verify_token_exp_claim(nil)
    |> verify_token_nbf_claim(nil)
    |> verify_token_claim_equals({"type", "refresh"})
    |> verify_token_claim_equals({"styp", "oauth2"})
    |> load_session(charon_config)
    |> verify_token_fresh(10)
  end

  defmacro __using__(config) do
    quote generated: true, bind_quoted: [charon_config: config] do
      mod_config = Internal.get_module_config(charon_config)
      repo = mod_config.repo
      client_schema_name = __MODULE__.Client
      client_context_name = __MODULE__.Clients
      authorization_schema_name = __MODULE__.Authorization
      authorization_context_name = __MODULE__.Authorizations
      grant_schema_name = __MODULE__.Grant
      grant_context_name = __MODULE__.Grants
      authorization_endpoint_name = __MODULE__.Plugs.AuthorizationEndpoint
      token_endpoint_name = __MODULE__.Plugs.TokenEndpoint

      schemas_and_contexts =
        %{
          grant: grant_schema_name,
          grants: grant_context_name,
          client: client_schema_name,
          clients: client_context_name,
          authorization: authorization_schema_name,
          authorizations: authorization_context_name
        }
        |> Macro.escape()

      @moduledoc """
      Entrypoint module for CharonOauth2.

      The following submodules are generated:
      - `#{authorization_schema_name}`
      - `#{authorization_context_name}`
       - `#{client_schema_name}`
       - `#{client_context_name}`
       - `#{grant_schema_name}`
       - `#{grant_context_name}`
       - `#{authorization_endpoint_name}`
       - `#{token_endpoint_name}`
      """

      location = Macro.Env.location(__ENV__)

      ###########
      # Schemas #
      ###########

      charon_config = Macro.escape(charon_config)
      grant_schema = Grant.generate(schemas_and_contexts, charon_config)
      client_schema = Client.generate(schemas_and_contexts, charon_config)
      auth_schema = Authorization.generate(schemas_and_contexts, charon_config)

      # generate a dummy module to suppress "assoc not found warnings"
      Module.create(authorization_schema_name, Authorization.gen_dummy(charon_config), location)

      Module.create(grant_schema_name, grant_schema, location)
      Module.create(client_schema_name, client_schema, location)
      # suppress "redefining module" warning, because we actually want to redefine it :)
      Code.compiler_options(ignore_module_conflict: true)
      Module.create(authorization_schema_name, auth_schema, location)
      Code.compiler_options(ignore_module_conflict: false)

      ############
      # Contexts #
      ############

      client_context = Clients.generate(schemas_and_contexts, repo)
      grant_context = Grants.generate(schemas_and_contexts, repo)
      authorization_context = Authorizations.generate(schemas_and_contexts, repo)

      Module.create(client_context_name, client_context, location)
      Module.create(grant_context_name, grant_context, location)
      Module.create(authorization_context_name, authorization_context, location)

      #########
      # Plugs #
      #########

      authorization_endpoint = AuthorizationEndpoint.generate(schemas_and_contexts, repo)
      Module.create(authorization_endpoint_name, authorization_endpoint, location)

      token_endpoint = TokenEndpoint.generate(schemas_and_contexts, repo)
      Module.create(token_endpoint_name, token_endpoint, location)
    end
  end
end
