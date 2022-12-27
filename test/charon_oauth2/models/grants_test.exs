defmodule CharonOauth2.Models.GrantsTest do
  use CharonOauth2.DataCase
  alias MyApp.CharonOauth2.{Grants, Grant}
  import MyApp.Seeds

  @config MyApp.CharonOauth2.Config.get()

  doctest Grants
end
