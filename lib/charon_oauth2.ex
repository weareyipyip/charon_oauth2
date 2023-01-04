defmodule CharonOauth2 do
  @moduledoc """
      use CharonOauth2, @charon_config
  """
  alias __MODULE__.Internal
  alias CharonOauth2.GenEctoMod.{Authorization, Authorizations, Client, Clients, Grant, Grants}

  @doc false
  def init_config(enum), do: __MODULE__.Config.from_enum(enum)

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

      @moduledoc """
      Entrypoint module for CharonOauth2.
      The following submodules are generated:
      - `#{@authorization_schema}`
      - `#{@authorization_context}`
       - `#{@client_schema}`
       - `#{@client_context}`
       - `#{@grant_schema}`
       - `#{@grant_context}`
      """

      ###########
      # Schemas #
      ###########

      charon_config = Macro.escape(@charon_config)
      grant_schema = Grant.generate(@authorization_schema, charon_config)
      client_schema = Client.generate(@authorization_schema, charon_config)

      auth_schema = Authorization.generate(@client_schema, @grant_schema, charon_config)

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

      client_context = Clients.generate(@client_schema, @repo)
      grant_context = Grants.generate(@grant_schema, @repo)
      authorization_context = Authorizations.generate(@authorization_schema, @repo)

      Module.create(@client_context, client_context, Macro.Env.location(__ENV__))
      Module.create(@grant_context, grant_context, Macro.Env.location(__ENV__))
      Module.create(@authorization_context, authorization_context, Macro.Env.location(__ENV__))
    end
  end
end
