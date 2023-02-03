defmodule CharonOauth2.Types.SeparatedStringOrdset do
  @moduledoc """
  Ecto type for casting a string with a pattern-separated list of values to an ordered-set string array.
  All pattern types of `String.split/3` are supported.
  Empty strings are trimmed from the result by default.

  ## Example

      schema "separated_things" do
        field :comma_separated, SeparatedStringOrdset, pattern: ","
        field :comma_or_semicolon_separated, SeparatedStringOrdset, pattern: ~w(, ;)
        field :regex_separated, SeparatedStringOrdset, pattern: ~r/,/
        field :comma_separated_with_empty_strings, SeparatedStringOrdset, pattern: ",", split_opts: []
      end

  ## Doctests

      @opts SeparatedStringOrdset.init(pattern: ",")

      iex> {:ok, ~w(bar baz foo)} = SeparatedStringOrdset.cast("foo,bar,baz,bar", @opts)
      iex> :error = SeparatedStringOrdset.cast([1, 2, "3"], @opts)
      iex> {:ok, ~w(1 2 true)} = SeparatedStringOrdset.cast("1,2,true", @opts)
      iex> {:ok, ~w(a b c)} = SeparatedStringOrdset.cast(~w(a b c), @opts)

      iex> opts = SeparatedStringOrdset.init(pattern: ",", split_opts: [])
      iex> {:ok, ["", "bar", "foo"]} = SeparatedStringOrdset.cast("foo,bar,", opts)
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

  def cast(<<bin::binary>>, {pattern, split_opts}) do
    {:ok, bin |> String.split(pattern, split_opts) |> :ordsets.from_list()}
  end

  def cast(other, _) do
    Type.cast(@base_type, other)
    |> case do
      {:ok, values} -> {:ok, :ordsets.from_list(values)}
      other -> other
    end
  end

  @impl Ecto.ParameterizedType
  def load(nil, _, _), do: {:ok, nil}
  def load(value, _, _), do: Type.load(@base_type, value)

  @impl Ecto.ParameterizedType
  def dump(nil, _, _), do: {:ok, nil}
  def dump(value, _, _), do: Type.dump(@base_type, value)
end
