alias MyApp.Repo
{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(Repo, :temporary)
{:ok, _pid} = Repo.start_link()

alias MyApp.CharonOauth2.{Client, Clients, Authorization, Authorizations, Grant, Grants}
alias CharonOauth2.Internal
import MyApp.Seeds

config = Charon.Config.from_enum(
              token_issuer: "stuff",
              get_base_secret: fn -> "supersecret" end,
              optional_modules: %{
                CharonOauth2 => %{
                  scopes: ~w(read write), repo: Repo, resource_owner_schema: MyApp.User}
              }
            )
