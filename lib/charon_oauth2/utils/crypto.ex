defmodule CharonOauth2.Utils.Crypto do
  @moduledoc """
  Encrypt/decrypt data using ChaCha20.
  """
  @encr_alg :chacha20
  @iv_size 16

  @doc """
  Encrypt the plaintext into a binary using the provided key.
  """
  @spec encrypt(binary, binary) :: binary
  def encrypt(plaintext, key) do
    iv = :crypto.strong_rand_bytes(@iv_size)
    # prefix a zero byte to detect decryption failure
    prefixed_plaintext = [0 | plaintext]
    encrypted = :crypto.crypto_one_time(@encr_alg, key, iv, prefixed_plaintext, true)
    <<iv::binary, encrypted::binary>>
  end

  @doc """
  Decrypt a binary using the provided key and return the plaintext or an error.
  """
  @spec decrypt(binary, binary) :: {:ok, binary} | {:error, :decryption_failed}
  def decrypt(_encrypted = <<iv::binary-size(@iv_size), ciphertext::binary>>, key) do
    case :crypto.crypto_one_time(@encr_alg, key, iv, ciphertext, false) do
      _prefixed_plaintext = <<0, plaintext::binary>> -> {:ok, plaintext}
      _ -> {:error, :decryption_failed}
    end
  end
end
