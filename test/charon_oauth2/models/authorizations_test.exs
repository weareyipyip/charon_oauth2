defmodule CharonOauth2.Models.AuthorizationsTest do
  use CharonOauth2.DataCase
  alias CharonOauth2.Models.{Authorizations, Authorization}
  import CharonOauth2.Test.TestSeeds

  @config Charon.Config.from_enum(
            token_issuer: "stuff",
            optional_modules: %{
              CharonOauth2 => %{scopes: ~w(read write)}
            }
          )

  doctest Authorizations
end
