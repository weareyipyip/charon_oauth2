import Config

config :logger, level: :warn

config :charon_oauth2, MyApp.Repo, database: "charon_oauth2_test", log: false
