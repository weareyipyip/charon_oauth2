defmodule CharonOauth2.Models.ClientsTest do
  use CharonOauth2.DataCase
  alias CharonOauth2.Models.{Clients, Client}
  import CharonOauth2.Seeds

  @config CharonOauth2.TestConfig.get()

  doctest Clients
end
