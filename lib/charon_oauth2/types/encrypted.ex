defmodule CharonOauth2.Types.Encrypted do
  @moduledoc """
  Ecto type for encrypted data. Takes any binary as input.

  Requires a column of type `:binary`.
  """
  alias Charon.Utils.KeyGenerator
  alias Charon.Internal.Crypto
  alias Ecto.ParameterizedType
  use ParameterizedType

  @base_type :binary
  @salt "charon_oauth2_type_encrypted"

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
  def load(nil, _, _), do: {:ok, nil}
  def load(value, _, config), do: Crypto.decrypt(value, get_key(config))

  @impl true
  def dump(nil, _, _), do: {:ok, nil}
  def dump(value, _, config), do: {:ok, Crypto.encrypt(value, get_key(config))}

  ###########
  # Private #
  ###########

  defp get_key(config), do: KeyGenerator.derive_key(config.get_base_secret.(), @salt)
end
