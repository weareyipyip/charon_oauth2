alias CharonOauth2.Repo
{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(Repo, :temporary)
{:ok, _pid} = Repo.start_link()

alias CharonOauth2.Models.{Client, Clients, Authorization, Authorizations, Grant, Grants}
alias CharonOauth2.Internal
import CharonOauth2.Seeds

config = Charon.Config.from_enum(
              token_issuer: "stuff",
              optional_modules: %{
                CharonOauth2 => %{scopes: ~w(read write)}
              }
            )
