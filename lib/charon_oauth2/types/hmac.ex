defmodule CharonOauth2.Types.Hmac do
  @moduledoc """
  Ecto type to only store a HMAC of the input data.
  This means the original data cannot be retrieved,
  but a record can be found by an exact equality match.

  Requires a column of type `:binary`.
  """
  alias Charon.Internal.KeyGenerator
  alias Ecto.ParameterizedType
  use ParameterizedType

  @base_type :binary
  @salt "charon_oauth2_type_hmac"

  @impl true
  def init(opts) do
    Keyword.fetch!(opts, :config)
  end

  @impl true
  def type(_), do: @base_type

  @impl true
  def cast(nil, _), do: {:ok, nil}
  def cast(<<value::binary>>, _), do: {:ok, value}
  def cast(_, _), do: :error

  @impl true
  def load(value, _, _), do: {:ok, value}

  @impl true
  def dump(nil, _, _), do: {:ok, nil}
  def dump(value, _, config), do: {:ok, :crypto.mac(:hmac, :sha256, get_key(config), value)}

  ###########
  # Private #
  ###########

  defp get_key(config), do: KeyGenerator.get_secret(@salt, 32, config)
end
