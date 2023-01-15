defmodule CharonOauth2.Models.ClientsTest do
  use CharonOauth2.DataCase
  alias MyApp.CharonOauth2.{Clients, Client, Authorizations}
  import MyApp.Seeds

  test "all bindings resolvable" do
    assert %Ecto.Query{} =
             Enum.reduce(
               Client.supported_preloads(),
               Client.named_binding(),
               &Client.resolve_binding(&2, &1)
             )
  end

  doctest Clients
end
