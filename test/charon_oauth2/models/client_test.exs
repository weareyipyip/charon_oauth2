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
             grant_types: {"client_credentials is not allowed for public clients", []}
           ]
  end

  test "grant_types must be subset of server-configured grant_types" do
    owner = insert_test_user()

    # Default config supports: authorization_code, refresh_token, client_credentials

    # All supported grant types should work
    assert {:ok, _client} =
             insert_test_client(%{
               owner_id: owner.id,
               grant_types: ~w(authorization_code refresh_token client_credentials)
             })

    assert %{
             grant_types: [
               "must be subset of authorization_code, client_credentials, refresh_token"
             ]
           } =
             insert_test_client(%{owner_id: owner.id, grant_types: ~w(boom)}) |> errors_on()
  end

  doctest Clients
end
