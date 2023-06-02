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
                seeder_overrides: %{
                  client: %{scope: ~w(read), grant_types: ~w(authorization_code)},
                  authorization: %{scope: ~w(read)},
                  grant: %{type: "authorization_code"}
                }
              }
            }
          )

  def get, do: @config
end
