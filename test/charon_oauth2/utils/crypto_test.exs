defmodule CharonOauth2.Utils.CryptoTest do
  use ExUnit.Case, async: true
  import CharonOauth2.Utils.Crypto

  @key :crypto.strong_rand_bytes(32)
  @wrong_key :crypto.strong_rand_bytes(32)

  describe "encryption" do
    test "works" do
      assert {:ok, "hello world"} = "hello world" |> encrypt(@key) |> decrypt(@key)
    end

    test "fails graciously" do
      assert {:error, :decryption_failed} = "hello world" |> encrypt(@key) |> decrypt(@wrong_key)
    end
  end
end
