defmodule CharonOauth2.Models.RefreshTokens do
  @moduledoc """
  Context to manage refresh_tokens
  """
  require Logger

  alias CharonOauth2.Internal
  alias CharonOauth2.Models.RefreshToken
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
      iex> {:ok, _} = refresh_token_params(@config) |> RefreshTokens.insert()

      iex> RefreshTokens.insert(%{}) |> errors_on()
      %{authorization_id: ["can't be blank"], expires_at: ["can't be blank"]}

      # authorization must exist
      iex> refresh_token_params(@config, authorization_id: -1) |> RefreshTokens.insert() |> errors_on()
      %{authorization: ["does not exist"]}
  """
  @spec insert(map) :: {:ok, RefreshToken.t()} | {:error, Changeset.t()}
  def insert(params) do
    params
    |> RefreshToken.insert_only_changeset()
    |> RefreshToken.changeset(params)
    |> @repo.insert()
  end

  @doc """
  Update a refresh_token.

  ## Examples / doctests

      # updates things
      iex> token = insert_test_refresh_token(@config)
      iex> {:ok, %{expires_at: ~U[2000-01-01 11:00:00Z]}} = RefreshTokens.update(token, %{expires_at: ~U[2000-01-01 11:00:00Z]})
  """
  @spec update(RefreshToken.t() | keyword(), map) ::
          {:ok, RefreshToken.t()} | {:error, Changeset.t()}
  def update(refresh_token = %RefreshToken{}, params) do
    refresh_token |> RefreshToken.changeset(params) |> @repo.update()
  end

  def update(clauses, params) do
    Internal.get_and_do(fn -> get_by(clauses) end, &update(&1, params))
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
end
