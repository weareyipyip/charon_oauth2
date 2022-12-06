import Config

config :charon_oauth2, ecto_repos: [CharonOauth2.Repo]

config :charon_oauth2, resource_owner_schema: CharonOauth2.Models.User, repo: CharonOauth2.Repo

config :charon_oauth2, CharonOauth2.Repo,
  hostname: System.get_env("POSTGRES_HOSTNAME", "localhost"),
  port: 5432,
  username: "postgres",
  password: "supersecret",
  database: "charon_oauth2",
  pool: Ecto.Adapters.SQL.Sandbox

import_config("#{Mix.env()}.exs")
