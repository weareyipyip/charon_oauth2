defmodule CharonOauth2.Internal do
  @moduledoc false
  alias Ecto.Changeset

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
  def get_and_do(getter, then_do, repo) do
    fn ->
      with thing = %{} <- getter.() do
        then_do.(thing)
      end
      |> case do
        {:ok, result} -> result
        {:error, err} -> repo.rollback(err)
        nil -> repo.rollback(:not_found)
      end
    end
    |> repo.transaction()
  end
end
