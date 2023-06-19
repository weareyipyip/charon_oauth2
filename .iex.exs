alias MyApp.Repo
{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(Repo, :temporary)
{:ok, _pid} = Repo.start_link()

alias MyApp.CharonOauth2.{Client, Clients, Authorization, Authorizations, Grant, Grants, TestSeeds}
alias CharonOauth2.Internal

config = Charon.Config.from_enum(
              token_issuer: "stuff",
              get_base_secret: fn -> "supersecret" end,
              optional_modules: %{
                CharonOauth2 => %{
                  scopes: ~w(read write), repo: Repo, resource_owner_schema: MyApp.User}
              }
            )

user = MyApp.User.changeset() |> Repo.insert!()
