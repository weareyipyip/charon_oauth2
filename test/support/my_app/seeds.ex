defmodule MyApp.Seeds do
  @moduledoc false
  alias MyApp.{User, Repo}
  alias MyApp.CharonOauth2.{Clients, Authorizations, Grants}
  alias CharonOauth2.Internal

  @config MyApp.CharonOauth2.Config.get()
  @mod_config Internal.get_module_config(@config)

  @redirect_uri "https://stuff"

  @default_client_params %{
    name: "MyApp",
    redirect_uris: [@redirect_uri],
    scope: ~w(read),
    grant_types: ~w(authorization_code),
    description: "Incredible app that totally respects your privacy."
  }

  def client_params(overrides \\ []) do
    id_field = @mod_config.resource_owner_id_column

    @default_client_params
    |> Map.merge(Map.new(overrides))
    |> Map.put_new_lazy(:owner_id, fn -> insert_test_user() |> Map.get(id_field) end)
  end

  def insert_test_client(overrides \\ []) do
    overrides |> client_params() |> Clients.insert() |> bang!()
  end

  def insert_test_user() do
    User.changeset() |> Repo.insert!()
  end

  @default_authorization_params %{scope: ~w(read)}

  def authorization_params(overrides \\ []) do
    id_field = @mod_config.resource_owner_id_column

    @default_authorization_params
    |> Map.merge(Map.new(overrides))
    |> Map.put_new_lazy(:resource_owner_id, fn -> insert_test_user() |> Map.get(id_field) end)
    |> Map.put_new_lazy(:client_id, fn -> insert_test_client().id end)
  end

  def insert_test_authorization(overrides \\ []) do
    overrides |> authorization_params() |> Authorizations.insert() |> bang!()
  end

  @default_grant_params %{redirect_uri: @redirect_uri, type: "authorization_code"}

  def grant_params(overrides \\ []) do
    @default_grant_params
    |> Map.merge(Map.new(overrides))
    |> Map.put_new_lazy(:authorization_id, fn -> insert_test_authorization().id end)
    |> case do
      map = %{resource_owner_id: _} ->
        map

      map = %{authorization_id: auth_id} ->
        if auth = Authorizations.get_by(id: auth_id) do
          Map.put(map, :resource_owner_id, auth.resource_owner_id)
        else
          Map.put(map, :resource_owner_id, -1)
        end
    end
  end

  def insert_test_grant(overrides \\ []) do
    overrides |> grant_params() |> Grants.insert() |> bang!()
  end

  ###########
  # Private #
  ###########

  defp bang!({:ok, thing}), do: thing
  defp bang!(err), do: err |> inspect(pretty: true) |> raise
end
