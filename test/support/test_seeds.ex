defmodule CharonOauth2.Test.TestSeeds do
  alias CharonOauth2.Test.{Repo, User}
  alias CharonOauth2.Models.{Clients}

  @default_client_params %{
    name: "MyApp",
    redirect_uris: ~w(http://stuff),
    scopes: ~w(read),
    grant_types: ~w()
  }

  def client_params(overrides \\ []) do
    @default_client_params
    |> Map.merge(Map.new(overrides))
    |> Map.put_new_lazy(:owner_id, fn -> insert_test_user().id end)
  end

  def insert_test_client(overrides \\ [], config) do
    overrides |> client_params() |> Clients.insert(config) |> ok_or_raise()
  end

  def insert_test_user() do
    User.changeset() |> Repo.insert!()
  end

  defp ok_or_raise({:ok, thing}), do: thing
  defp ok_or_raise(other), do: raise(other)
end
