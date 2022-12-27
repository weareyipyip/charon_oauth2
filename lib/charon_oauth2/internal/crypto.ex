defmodule CharonOauth2.Internal.Crypto do
  @moduledoc false
  @encr_alg :chacha20
  @iv_size 16

  @doc """
  Encrypt the plaintext into a binary using the provided key.
  """
  @spec encrypt(binary, binary) :: binary
  def encrypt(plaintext, key) do
    iv = :crypto.strong_rand_bytes(@iv_size)
    # prefix 32 zero bits to detect decryption failure
    plaintext = <<0::32, plaintext::binary>>
    encrypted = :crypto.crypto_one_time(@encr_alg, key, iv, plaintext, true)
    <<iv::binary, encrypted::binary>>
  end

  @doc """
  Decrypt a binary using the provided key and return the plaintext or an error.
  """
  @spec decrypt(binary, binary) :: {:ok, binary} | {:error, :decryption_failed}
  def decrypt(_encrypted = <<iv::binary-size(16), ciphertext::binary>>, key) do
    case :crypto.crypto_one_time(@encr_alg, key, iv, ciphertext, false) do
      <<0::32, plaintext::binary>> -> {:ok, plaintext}
      _ -> {:error, :decryption_failed}
    end
  end
end
