defmodule CharonOauth2.Test.User do
  use Ecto.Schema

  schema "users" do
  end

  def changeset() do
    Ecto.Changeset.change(%__MODULE__{}, %{})
  end
end
