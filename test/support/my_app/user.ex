defmodule MyApp.User do
  @moduledoc false
  use Ecto.Schema
  alias MyApp.CharonOauth2.{Client, Authorization, Grant}

  schema "users" do
    has_many :authorizations, Authorization, foreign_key: :resource_owner_id
    has_many :grants, Grant, foreign_key: :resource_owner_id
    has_many :client, Client, foreign_key: :owner_id
  end

  def changeset() do
    Ecto.Changeset.change(%__MODULE__{}, %{})
  end
end
