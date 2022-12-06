defmodule CharonOauth2.Models.RefreshTokens do
  @moduledoc """
  Context to manage refresh_tokens
  """
  require Logger

  alias CharonOauth2.Internal
  alias CharonOauth2.Models.RefreshToken
  import Ecto.Query, only: [from: 2]
  @repo Application.compile_env!(:charon_oauth2, :repo)

  @doc """
  Get a single refresh_token by one or more clauses, optionally with preloads.
  Returns nil if RefreshToken cannot be found.

  Supported preloads: `#{inspect(RefreshToken.supported_preloads())}`

  ## Doctests

      iex> refresh_token = insert_test_refresh_token(@config)
      iex> %RefreshToken{} = RefreshTokens.get_by(id: refresh_token.id)
      iex> nil = RefreshTokens.get_by(id: Ecto.UUID.generate())

      # preloads things
      iex> refresh_token = insert_test_refresh_token(@config)
      iex> %{authorization: %{client: %{id: _}}} = RefreshTokens.get_by([id: refresh_token.id], RefreshToken.supported_preloads)
  """
  @spec get_by(keyword | map, [atom]) :: RefreshToken.t() | nil
  def get_by(clauses, preloads \\ []) do
    preloads |> RefreshToken.preload() |> @repo.get_by(clauses)
  end

  @doc """
  Get a list of all oauth2 refresh_tokens.

  Supported preloads: `#{inspect(RefreshToken.supported_preloads())}`

  ## Doctests

      iex> insert_test_refresh_token(@config)
      iex> [%RefreshToken{}] = RefreshTokens.all()
  """
  @spec all([atom]) :: [RefreshToken.t()]
  def all(preloads \\ []) do
    preloads |> RefreshToken.preload() |> @repo.all()
  end

  @doc """
  Insert a new refresh_token

  ## Examples / doctests

      # succesfully creates a refresh_token
      iex> {:ok, _} = refresh_token_params(@config) |> RefreshTokens.insert(@config)

      iex> RefreshTokens.insert(%{}, @config) |> errors_on()
      %{authorization_id: ["can't be blank"]}

      # authorization must exist
      iex> refresh_token_params(@config, authorization_id: -1) |> RefreshTokens.insert(@config) |> errors_on()
      %{authorization: ["does not exist"]}
  """
  @spec insert(map, Charon.Config.t()) :: {:ok, RefreshToken.t()} | {:error, Changeset.t()}
  def insert(params, config) do
    params
    |> RefreshToken.insert_only_changeset(config)
    |> @repo.insert()
  end

  @doc """
  Delete a refresh_token.

  ## Examples / doctests

      # refresh_token must exist
      iex> {:error, :not_found} = RefreshTokens.delete(id: Ecto.UUID.generate())

      # succesfully deletes a refresh_token
      iex> refresh_token = insert_test_refresh_token(@config)
      iex> {:ok, _} = RefreshTokens.delete([id: refresh_token.id])
      iex> {:error, :not_found} = RefreshTokens.delete([id: refresh_token.id])
  """
  @spec delete(RefreshToken.t() | keyword) :: {:ok, RefreshToken.t()} | {:error, :not_found}
  def delete(refresh_token = %RefreshToken{}), do: @repo.delete(refresh_token)

  def delete(clauses) do
    Internal.get_and_do(fn -> get_by(clauses) end, &delete/1)
  end

  @doc """
  Delete all oauth2_refresh_tokens older than their `expires_at` timestamp.

  ## Examples

      iex> valid = insert_test_refresh_token(@config)
      iex> expired = insert_test_refresh_token(@config)
      iex> past = DateTime.from_unix!(System.os_time(:second) - 10)
      iex> from(t in RefreshToken, where: t.id == ^expired.id) |> Repo.update_all(set: [expires_at: past])
      iex> RefreshTokens.delete_expired()
      iex> valid_id = valid.id
      iex> [%{id: ^valid_id}] = RefreshTokens.all()
  """
  @spec delete_expired :: {integer, nil}
  def delete_expired() do
    from(t in RefreshToken, where: t.expires_at < ago(0, "second"))
    |> @repo.delete_all()
    |> tap(fn {n, _} -> Logger.info("Deleted #{n} expired oauth2_refresh_tokens") end)
  end
end
