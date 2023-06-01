defmodule CharonOauth2.Seeders.Client do

  @default_client %{
    redirect_uri: "hi",
    type: "authorization_code"
  }

  def insert_test_client(insertgrant, overrides) do
    overrides
    |> Map.merge(@default_client)
    |> insertgrant.()
  end
end
