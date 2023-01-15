defmodule CharonOauth2.Internal do
  @moduledoc false
  alias Ecto.Changeset

  @doc false
  @spec multifield_apply(Changeset.t(), [atom], (Changeset.t(), atom -> Changeset.t())) ::
          Changeset.t()
  def multifield_apply(changeset, fields, function) do
    Enum.reduce(fields, changeset, &function.(&2, &1))
  end

  def validate_ordset_element(changeset, field, data, msg \\ "invalid entry") do
    Changeset.validate_change(changeset, field, fn _, value ->
      if :ordsets.is_element(value, data), do: [], else: [{field, msg}]
    end)
  end

  @doc false
  @spec validate_sub_ordset(Changeset.t(), atom, Enum.t(), String.t()) :: Changeset.t()
  def validate_sub_ordset(changeset, field, data, msg \\ "has an invalid entry") do
    Changeset.validate_change(changeset, field, fn _, value ->
      if :ordsets.is_subset(value, data), do: [], else: [{field, msg}]
    end)
  end

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

  def upsert(getter, update, insert, repo) do
    fn ->
      case getter.() do
        nil -> insert.()
        found = %{} -> update.(found)
      end
      |> case do
        {:ok, result} -> result
        {:error, err} -> repo.rollback(err)
      end
    end
    |> repo.transaction()
  end

  @doc false
  def column_type_to_ecto_type(:bigserial), do: :id
  def column_type_to_ecto_type(:serial), do: :id
  def column_type_to_ecto_type(:uuid), do: :binary_id

  defmacro set_contains_any(field, value) do
    quote do
      fragment("? && ?", unquote(field), ^unquote(value))
    end
  end
end
