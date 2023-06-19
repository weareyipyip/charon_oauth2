defmodule MyApp.CharonOauth2.Config do
  def get_secret(), do: "supersecret"
  def get_auth_uri, do: "https://mywebapp.com/authorize"

  @config Charon.Config.from_enum(
            token_issuer: "stuff",
            get_base_secret: &__MODULE__.get_secret/0,
            session_store_module: Charon.SessionStore.DummyStore,
            optional_modules: %{
              CharonOauth2 => %{
                scopes: ~w(read write party),
                resource_owner_schema: MyApp.User,
                repo: MyApp.Repo,
                test_seed_defaults: [authorization: [scope: ~w(read)], client: [scope: ~w(read)]]
              }
            }
          )

  def get, do: @config
end
