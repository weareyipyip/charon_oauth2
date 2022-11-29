defmodule CharonOauth2.Internal do
  @moduledoc false
  alias Ecto.Changeset

  @repo Application.compile_env!(:charon_oauth2, :repo)

  @doc false
  @spec multifield_apply(Changeset.t(), [atom], (Changeset.t(), atom -> Changeset.t())) ::
          Changeset.t()
  def multifield_apply(changeset, fields, function) do
    Enum.reduce(fields, changeset, &function.(&2, &1))
  end

  @doc false
  def get_module_config(%{optional_modules: %{CharonOauth2 => config}}), do: config

  @doc false
  def random_string(bits \\ 256) do
    bits |> div(8) |> :crypto.strong_rand_bytes() |> Base.url_encode64()
  end

  def get_and_do(getter, then_do) do
    fn ->
      with thing = %{} <- getter.() do
        then_do.(thing)
      end
      |> case do
        {:ok, result} -> result
        {:error, err} -> @repo.rollback(err)
        nil -> @repo.rollback(:not_found)
      end
    end
    |> @repo.transaction()
  end
end
