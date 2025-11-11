defmodule CharonOauth2.Models.ClientTest do
  use CharonOauth2.DataCase
  alias MyApp.CharonOauth2.{Clients, Client, Authorizations}
  import MyApp.CharonOauth2.TestSeeds

  test "cannot be public when it has the client_credentials grant" do
    owner = insert_test_user()

    {:error, result} =
      insert_test_client(%{
        owner_id: owner.id,
        grant_types: ~w(refresh_token client_credentials),
        client_type: "public"
      })

    assert result.errors == [
             client_type: {"Can not be public for client_credential clients", []}
           ]
  end

  doctest Clients
end
