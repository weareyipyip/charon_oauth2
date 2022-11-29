defmodule CharonOauth2.Types.SeparatedString do
  @moduledoc """
  Ecto type for casting a string with a pattern-separated list of values to a string array.
  All pattern types of `String.split/3` are supported.
  Empty strings are trimmed from the result by default.

  ## Example

      schema "separated_things" do
        field :comma_separated, SeparatedString, pattern: ","
        field :comma_or_semicolon_separated, SeparatedString, pattern: ~w(, ;)
        field :regex_separated, SeparatedString, pattern: ~r/,/
        field :comma_separated_with_empty_strings, SeparatedString, pattern: ",", split_opts: []
      end

  ## Doctests

      @opts SeparatedString.init(pattern: ",")

      iex> {:ok, ~w(foo bar baz)} = SeparatedString.cast("foo,bar,baz", @opts)
      iex> :error = SeparatedString.cast([1, 2, "3"], @opts)
      iex> {:ok, ~w(1 2 true)} = SeparatedString.cast("1,2,true", @opts)
      iex> {:ok, ~w(a b c)} = SeparatedString.cast(["a", "b", "c"], @opts)

      iex> opts = SeparatedString.init(pattern: ",", split_opts: [])
      iex> {:ok, ["foo", "bar", ""]} = SeparatedString.cast("foo,bar,", opts)
  """
  alias Ecto.ParameterizedType
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
  def cast(<<bin::binary>>, {pattern, split_opts}) do
    bin |> String.split(pattern, split_opts) |> then(&Ecto.Type.cast(@base_type, &1))
  end

  def cast(other, _), do: Ecto.Type.cast(@base_type, other)

  @impl Ecto.ParameterizedType
  def load(value, _, _), do: Ecto.Type.load(@base_type, value)

  @impl Ecto.ParameterizedType
  def dump(value, _, _), do: Ecto.Type.dump(@base_type, value)
end
