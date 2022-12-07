defmodule CharonOauth2.Seeds do
  @moduledoc false
  alias CharonOauth2.{Repo}
  alias CharonOauth2.Models.{Clients, Authorizations, Grants, User}

  @redirect_uri "http://stuff"

  @default_client_params %{
    name: "MyApp",
    redirect_uris: [@redirect_uri],
    scopes: ~w(read),
    grant_types: ~w(authorization_code)
  }

  def client_params(overrides \\ []) do
    @default_client_params
    |> Map.merge(Map.new(overrides))
    |> Map.put_new_lazy(:owner_id, fn -> insert_test_user().id end)
  end

  def insert_test_client(config, overrides \\ []) do
    overrides |> client_params() |> Clients.insert(config) |> bang!()
  end

  def insert_test_user() do
    User.changeset() |> Repo.insert!()
  end

  @default_authorization_params %{scopes: ~w(read)}

  def authorization_params(config, overrides \\ []) do
    @default_authorization_params
    |> Map.merge(Map.new(overrides))
    |> Map.put_new_lazy(:resource_owner_id, fn -> insert_test_user().id end)
    |> Map.put_new_lazy(:client_id, fn -> insert_test_client(config).id end)
  end

  def insert_test_authorization(config, overrides \\ []) do
    authorization_params(config, overrides) |> Authorizations.insert(config) |> bang!()
  end

  @default_grant_params %{redirect_uri: @redirect_uri, type: "authorization_code"}

  def grant_params(config, overrides \\ []) do
    @default_grant_params
    |> Map.merge(Map.new(overrides))
    |> Map.put_new_lazy(:authorization_id, fn -> insert_test_authorization(config).id end)
  end

  def insert_test_grant(config, overrides \\ []) do
    grant_params(config, overrides) |> Grants.insert(config) |> bang!()
  end

  ###########
  # Private #
  ###########

  defp bang!({:ok, thing}), do: thing
  defp bang!(err), do: err |> inspect(pretty: true) |> raise
end
