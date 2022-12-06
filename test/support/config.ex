defmodule CharonOauth2.TestConfig do
  @config Charon.Config.from_enum(
            token_issuer: "stuff",
            optional_modules: %{
              CharonOauth2 => %{scopes: ~w(read write)}
            }
          )

  def get, do: @config
end
