import Config

config :charon_oauth2, ecto_repos: [MyApp.Repo]

config :charon_oauth2, CharonOauth2.MyApp,
  resource_owner_schema: MyApp.User,
  repo: MyApp.Repo

config :charon_oauth2, MyApp.Repo,
  hostname: System.get_env("POSTGRES_HOSTNAME", "localhost"),
  port: 5432,
  username: "postgres",
  password: "supersecret",
  database: "charon_oauth2",
  pool: Ecto.Adapters.SQL.Sandbox

import_config("#{Mix.env()}.exs")
