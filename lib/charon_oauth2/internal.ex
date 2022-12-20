defmodule CharonOauth2.Internal do
  @moduledoc false
  alias Ecto.Changeset

  def get_repo(), do: Application.get_env(:charon_oauth2, :repo)

  @doc false
  @spec multifield_apply(Changeset.t(), [atom], (Changeset.t(), atom -> Changeset.t())) ::
          Changeset.t()
  def multifield_apply(changeset, fields, function) do
    Enum.reduce(fields, changeset, &function.(&2, &1))
  end

  @doc false
  @spec to_set(Ecto.Changeset.t(), atom) :: Ecto.Changeset.t()
  def to_set(changeset, field), do: Changeset.update_change(changeset, field, &Enum.uniq/1)

  @doc false
  def get_module_config(%{optional_modules: %{CharonOauth2 => config}}), do: config

  @doc false
  def random_string(bits \\ 256) do
    bits |> div(8) |> :crypto.strong_rand_bytes() |> Base.url_encode64()
  end

  @doc false
  def get_and_do(getter, then_do) do
    fn ->
      with thing = %{} <- getter.() do
        then_do.(thing)
      end
      |> case do
        {:ok, result} -> result
        {:error, err} -> get_repo().rollback(err)
        nil -> get_repo().rollback(:not_found)
      end
    end
    |> get_repo().transaction()
  end
end
