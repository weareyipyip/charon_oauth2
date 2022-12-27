defmodule CharonOauth2.Models.ClientsTest do
  use CharonOauth2.DataCase
  alias MyApp.CharonOauth2.{Clients, Client}
  import MyApp.Seeds

  @config MyApp.CharonOauth2.Config.get()

  doctest Clients
end
