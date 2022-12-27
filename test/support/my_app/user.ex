defmodule MyApp.User do
  @moduledoc false
  use Ecto.Schema

  schema "users" do
  end

  def changeset() do
    Ecto.Changeset.change(%__MODULE__{}, %{})
  end
end
