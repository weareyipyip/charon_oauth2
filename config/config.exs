import Config

config :charon_oauth2, resource_owner_schema: CharonOauth2.Test.User, repo: CharonOauth2.Test.Repo

config :charon_oauth2, CharonOauth2.Test.Repo,
  hostname: "localhost",
  port: 5432,
  username: "postgres",
  password: "supersecret",
  database: "charon_oauth2",
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false
