defmodule CharonOauth2.MixProject do
  use Mix.Project

  def project do
    [
      app: :charon_oauth2,
      version: "0.0.0+development",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: """
      Add Oauth2 capabilities to a Charon-protected server.
      """,
      package: [
        licenses: ["Apache-2.0"],
        links: %{github: "https://github.com/weareyipyip/charon_oauth2"},
        source_url: "https://github.com/weareyipyip/charon_oauth2"
      ],
      source_url: "https://github.com/weareyipyip/charon_oauth2",
      name: "CharonOauth2",
      docs: [
        source_ref: "main",
        extras: ["./README.md", "./example-auth-page.md"],
        main: "readme"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.5"},
      {:ecto_sql, "~> 3.0"},
      {:plug, "~> 1.11"},
      {:charon, "~> 3.1"},
      {:ex_doc, "~> 0.21", only: [:dev, :test], runtime: false},
      {:postgrex, ">= 0.0.0", only: [:dev, :test]},
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false}
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "ecto.migrate": "ecto.migrate --migrations-path test/support/my_app/migrations"
    ]
  end
end
