defmodule CharonOauth2.Models.GrantsTest do
  use CharonOauth2.DataCase
  alias CharonOauth2.Models.{Grants, Grant}
  import CharonOauth2.Seeds

  @config CharonOauth2.TestConfig.get()

  doctest Grants
end
