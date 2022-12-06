defmodule CharonOauth2.Models.Grants do
  @moduledoc """
  Context to manage grants
  """
  require Logger

  alias CharonOauth2.Internal
  alias CharonOauth2.Models.Grant
  @repo Application.compile_env!(:charon_oauth2, :repo)

  @doc """
  Get a single grant by one or more clauses, optionally with preloads.
  Returns nil if Grant cannot be found.

  Supported preloads: `#{inspect(Grant.supported_preloads())}`

  ## Doctests

      iex> grant = insert_test_grant(@config)
      iex> %Grant{} = Grants.get_by(id: grant.id)
      iex> nil = Grants.get_by(id: grant.id + 1)

      # preloads things
      iex> grant = insert_test_grant(@config)
      iex> %{authorization: %{client: %{id: _}}} = Grants.get_by([id: grant.id], Grant.supported_preloads)
  """
  @spec get_by(keyword | map, [atom]) :: Grant.t() | nil
  def get_by(clauses, preloads \\ []) do
    preloads |> Grant.preload() |> @repo.get_by(clauses)
  end

  @doc """
  Get a list of all oauth2 grants.

  Supported preloads: `#{inspect(Grant.supported_preloads())}`

  ## Doctests

      iex> insert_test_grant(@config)
      iex> [%Grant{}] = Grants.all()
  """
  @spec all([atom]) :: [Grant.t()]
  def all(preloads \\ []) do
    preloads |> Grant.preload() |> @repo.all()
  end

  @doc """
  Insert a new grant

  ## Examples / doctests

      # succesfully creates a grant
      iex> {:ok, _} = grant_params(@config) |> Grants.insert()

      iex> Grants.insert(%{}) |> errors_on()
      %{authorization_id: ["can't be blank"], redirect_uri: ["can't be blank"], type: ["can't be blank"]}

      # authorization must exist
      iex> grant_params(@config, authorization_id: -1) |> Grants.insert() |> errors_on()
      %{authorization: ["does not exist"]}

      # type must be one of client grant_type's
      iex> client = insert_test_client(@config, grant_types: ~w(refresh_token))
      iex> authorization = insert_test_authorization(@config, client_id: client.id)
      iex> grant_params(@config, authorization_id: authorization.id) |> Grants.insert() |> errors_on()
      %{type: ["not supported by client"]}
  """
  @spec insert(map) :: {:ok, Grant.t()} | {:error, Changeset.t()}
  def insert(params) do
    params |> Grant.insert_only_changeset() |> Grant.changeset(params) |> @repo.insert()
  end

  @doc """
  Update a grant.

  ## Examples / doctests

      # redirect_uri must be one of client redirect_uri's
      iex> insert_test_grant(@config) |> Grants.update(%{redirect_uri: "https://boom.com"}) |> errors_on()
      %{redirect_uri: ["does not match client"]}
  """
  @spec update(Grant.t() | keyword(), map) ::
          {:ok, Grant.t()} | {:error, Changeset.t()}
  def update(grant = %Grant{}, params) do
    grant |> Grant.changeset(params) |> @repo.update()
  end

  def update(clauses, params) do
    Internal.get_and_do(fn -> get_by(clauses) end, &update(&1, params))
  end

  @doc """
  Delete a grant.

  ## Examples / doctests

      # grant must exist
      iex> {:error, :not_found} = Grants.delete(id: -1)

      # succesfully deletes a grant
      iex> grant = insert_test_grant(@config)
      iex> {:ok, _} = Grants.delete([id: grant.id])
      iex> {:error, :not_found} = Grants.delete([id: grant.id])
  """
  @spec delete(Grant.t() | keyword) :: {:ok, Grant.t()} | {:error, :not_found}
  def delete(grant = %Grant{}), do: @repo.delete(grant)

  def delete(clauses) do
    Internal.get_and_do(fn -> get_by(clauses) end, &delete/1)
  end
end
