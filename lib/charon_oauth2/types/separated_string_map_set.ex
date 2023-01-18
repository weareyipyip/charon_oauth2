defmodule CharonOauth2.Types.SeparatedStringMapSet do
  @moduledoc """
  Ecto type for casting a string with a pattern-separated list of values to an ordered-set string array.
  All pattern types of `String.split/3` are supported.
  Empty strings are trimmed from the result by default.

  ## Example

      schema "separated_things" do
        field :comma_separated, SeparatedStringMapSet, pattern: ","
        field :comma_or_semicolon_separated, SeparatedStringMapSet, pattern: ~w(, ;)
        field :regex_separated, SeparatedStringMapSet, pattern: ~r/,/
        field :comma_separated_with_empty_strings, SeparatedStringMapSet, pattern: ",", split_opts: []
      end

  ## Doctests

      @opts SeparatedStringMapSet.init(pattern: ",")

      iex> SeparatedStringMapSet.cast("foo,bar,baz,bar", @opts)
      {:ok, MapSet.new(["bar", "baz", "foo"])}
      iex> :error = SeparatedStringMapSet.cast([1, 2, "3"], @opts)
      iex> SeparatedStringMapSet.cast("1,2,true", @opts)
      {:ok, MapSet.new(["1", "2", "true"])}
      iex> SeparatedStringMapSet.cast(~w(a b c), @opts)
      {:ok, MapSet.new(["a", "b", "c"])}

      iex> opts = SeparatedStringMapSet.init(pattern: ",", split_opts: [])
      iex> SeparatedStringMapSet.cast("foo,bar,", opts)
      {:ok, MapSet.new(["", "bar", "foo"])}
  """
  alias Ecto.ParameterizedType
  alias Ecto.Type
  use Ecto.ParameterizedType

  @base_type {:array, :string}
  @default_split_opts [trim: true]

  @impl ParameterizedType
  def init(opts) do
    opts = Map.new(opts)
    pattern = opts[:pattern] || raise "pattern must be set"
    split_opts = opts[:split_opts] || @default_split_opts
    {pattern, split_opts}
  end

  @impl Ecto.ParameterizedType
  def type(_), do: @base_type

  @impl Ecto.ParameterizedType
  def cast(nil, _), do: {:ok, nil}

  def cast(%MapSet{} = set, _), do: {:ok, set}

  def cast(<<bin::binary>>, {pattern, split_opts}) do
    {:ok, bin |> String.split(pattern, split_opts) |> MapSet.new()}
  end

  def cast(other, _) do
    Type.cast(@base_type, other)
    |> case do
      {:ok, values} -> {:ok, MapSet.new(values)}
      other -> other
    end
  end

  @impl Ecto.ParameterizedType
  def load(nil, _, _), do: {:ok, nil}

  def load(value, _, _) do
    Type.load(@base_type, value)
    |> case do
      {:ok, values} -> {:ok, MapSet.new(values)}
      other -> other
    end
  end

  @impl Ecto.ParameterizedType
  def dump(nil, _, _), do: {:ok, nil}
  def dump(value, _, _), do: Type.dump(@base_type, MapSet.to_list(value))
end
