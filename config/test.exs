import Config

config :logger, level: :warning

config :charon_oauth2, MyApp.Repo, database: "charon_oauth2_test", log: false
