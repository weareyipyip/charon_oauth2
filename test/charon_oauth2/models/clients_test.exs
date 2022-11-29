defmodule CharonOauth2.Models.ClientsTest do
  use CharonOauth2.DataCase
  alias CharonOauth2.Models.Clients
  import CharonOauth2.Test.TestSeeds

  @config Charon.Config.from_enum(
            token_issuer: "stuff",
            optional_modules: %{
              CharonOauth2 => %{scopes: ~w(read write)}
            }
          )

  doctest Clients
end
