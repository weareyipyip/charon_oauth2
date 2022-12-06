defmodule CharonOauth2.Models.RefreshTokensTest do
  use CharonOauth2.DataCase
  alias CharonOauth2.Models.{RefreshTokens, RefreshToken}
  alias CharonOauth2.Repo
  import CharonOauth2.Seeds

  @config CharonOauth2.TestConfig.get()

  doctest RefreshTokens
end
