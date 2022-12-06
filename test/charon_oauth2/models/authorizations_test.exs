defmodule CharonOauth2.Models.AuthorizationsTest do
  use CharonOauth2.DataCase
  alias CharonOauth2.Models.{Authorizations, Authorization}
  import CharonOauth2.Seeds

  @config CharonOauth2.TestConfig.get()
  doctest Authorizations
end
