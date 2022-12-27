defmodule MyApp.CharonOauth2.Config do
  def get_secret(), do: "supersecret"

  @config Charon.Config.from_enum(
            token_issuer: "stuff",
            get_base_secret: &__MODULE__.get_secret/0,
            optional_modules: %{
              CharonOauth2 => %{
                scopes: ~w(read write),
                resource_owner_schema: MyApp.User,
                repo: MyApp.Repo
              }
            }
          )

  def get, do: @config
end
