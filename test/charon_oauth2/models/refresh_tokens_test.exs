defmodule CharonOauth2.Models.RefreshTokensTest do
  use CharonOauth2.DataCase
  alias CharonOauth2.Models.{RefreshTokens, RefreshToken}
  import CharonOauth2.Seeds

  @config CharonOauth2.TestConfig.get()

  doctest RefreshTokens
end
