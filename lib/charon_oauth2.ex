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
    |> verify_refresh_token_fresh(10)
  end

  defmacro __using__(config) do
    quote location: :keep, generated: true do
      @charon_config unquote(config)
      @mod_config Internal.get_module_config(@charon_config)
      @repo @mod_config.repo
      @user_schema @mod_config.resource_owner_schema
      @client_schema __MODULE__.Client
      @client_context __MODULE__.Clients
      @authorization_schema __MODULE__.Authorization
      @authorization_context __MODULE__.Authorizations
      @grant_schema __MODULE__.Grant
      @grant_context __MODULE__.Grants
      @authorization_endpoint __MODULE__.Plugs.AuthorizationEndpoint
      @token_endpoint __MODULE__.Plugs.TokenEndpoint
      @schemas_and_contexts %{
        grant: @grant_schema,
        grants: @grant_context,
        client: @client_schema,
        clients: @client_context,
        authorization: @authorization_schema,
        authorizations: @authorization_context
      }

      @moduledoc """
      Entrypoint module for CharonOauth2.

      The following submodules are generated:
      - `#{@authorization_schema}`
      - `#{@authorization_context}`
       - `#{@client_schema}`
       - `#{@client_context}`
       - `#{@grant_schema}`
       - `#{@grant_context}`
       - `#{@authorization_endpoint}`
       - `#{@token_endpoint}`
      """

      ###########
      # Schemas #
      ###########

      charon_config = Macro.escape(@charon_config)
      grant_schema = Grant.generate(@schemas_and_contexts, charon_config)
      client_schema = Client.generate(@schemas_and_contexts, charon_config)
      auth_schema = Authorization.generate(@schemas_and_contexts, charon_config)

      # generate a dummy module to suppress "assoc not found warnings"
      Module.create(
        @authorization_schema,
        Authorization.gen_dummy(charon_config),
        Macro.Env.location(__ENV__)
      )

      Module.create(@grant_schema, grant_schema, Macro.Env.location(__ENV__))
      Module.create(@client_schema, client_schema, Macro.Env.location(__ENV__))
      # suppress "redefining module" warning, because we actually want to redefine it :)
      Code.compiler_options(ignore_module_conflict: true)
      Module.create(@authorization_schema, auth_schema, Macro.Env.location(__ENV__))
      Code.compiler_options(ignore_module_conflict: false)

      ############
      # Contexts #
      ############

      client_context = Clients.generate(@schemas_and_contexts, @repo)
      grant_context = Grants.generate(@schemas_and_contexts, @repo)
      authorization_context = Authorizations.generate(@schemas_and_contexts, @repo)

      Module.create(@client_context, client_context, Macro.Env.location(__ENV__))
      Module.create(@grant_context, grant_context, Macro.Env.location(__ENV__))
      Module.create(@authorization_context, authorization_context, Macro.Env.location(__ENV__))

      #########
      # Plugs #
      #########

      authorization_endpoint = AuthorizationEndpoint.generate(@schemas_and_contexts, @repo)
      Module.create(@authorization_endpoint, authorization_endpoint, Macro.Env.location(__ENV__))
      token_endpoint = TokenEndpoint.generate(@schemas_and_contexts, @repo)
      Module.create(@token_endpoint, token_endpoint, Macro.Env.location(__ENV__))
    end
  end
end
