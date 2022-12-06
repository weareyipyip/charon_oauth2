defmodule CharonOauth2.Models.Authorizations do
  @moduledoc """
  Context to manage authorizations
  """
  require Logger

  alias CharonOauth2.Internal
  alias CharonOauth2.Models.Authorization
  @repo Application.compile_env!(:charon_oauth2, :repo)

  @doc """
  Get a single authorization by one or more clauses, optionally with preloads.
  Returns nil if Authorization cannot be found.

  Supported preloads: `#{inspect(Authorization.supported_preloads())}`

  ## Doctests

      iex> authorization = insert_test_authorization(@config)
      iex> %Authorization{} = Authorizations.get_by(id: authorization.id)
      iex> nil = Authorizations.get_by(id: authorization.id + 1)

      # preloads things
      iex> authorization = insert_test_authorization(@config)
      iex> %{resource_owner: %{id: _}, client: %{id: _}} = Authorizations.get_by([id: authorization.id], Authorization.supported_preloads)
  """
  @spec get_by(keyword | map, [atom]) :: Authorization.t() | nil
  def get_by(clauses, preloads \\ []) do
    preloads |> Authorization.preload() |> @repo.get_by(clauses)
  end

  @doc """
  Get a list of all oauth2 authorizations.

  Supported preloads: `#{inspect(Authorization.supported_preloads())}`

  ## Doctests

      iex> insert_test_authorization(@config)
      iex> [%Authorization{}] = Authorizations.all()
  """
  @spec all([atom]) :: [Authorization.t()]
  def all(preloads \\ []) do
    preloads |> Authorization.preload() |> @repo.all()
  end

  @doc """
  Insert a new authorization

  ## Examples / doctests

      # succesfully creates an authorization
      iex> {:ok, _} = authorization_params(@config) |> Authorizations.insert(@config)

      # a user can authorize a client only once
      iex> {:ok, authorization} = authorization_params(@config) |> Authorizations.insert(@config)
      iex> authorization_params(@config, client_id: authorization.client_id, resource_owner_id: authorization.resource_owner_id) |> Authorizations.insert(@config) |> errors_on()
      %{client_id: ["user already authorized this client"]}

      # owner and client must exist
      iex> authorization_params(@config, resource_owner_id: -1) |> Authorizations.insert(@config) |> errors_on()
      %{resource_owner: ["does not exist"]}
      iex> authorization_params(@config, client_id: Ecto.UUID.generate()) |> Authorizations.insert(@config) |> errors_on()
      %{client: ["does not exist"]}

      iex> Authorizations.insert(%{}, @config) |> errors_on()
      %{scopes: ["can't be blank"], client_id: ["can't be blank"], resource_owner_id: ["can't be blank"]}
  """
  @spec insert(map, Charon.Config.t()) :: {:ok, Authorization.t()} | {:error, Changeset.t()}
  def insert(params, config) do
    params
    |> Authorization.insert_only_changeset()
    |> Authorization.changeset(params, config)
    |> @repo.insert()
  end

  @doc """
  Update an authorization.

  ## Examples / doctests

      # scopes must be subset of configured scopes and of client scopes
      iex> insert_test_authorization(@config) |> Authorizations.update(%{scopes: ~w(cry)}, @config) |> errors_on()
      %{scopes: ["must be subset of read, write"]}
      iex> insert_test_authorization(@config) |> Authorizations.update(%{scopes: ~w(write write)}, @config) |> errors_on()
      %{scopes: ["client not allowed to access scope(s): write"]}

      # # client and resource owner can't be updated
      # iex> %{client_id: client_id, resource_owner_id: owner_id} = insert_test_authorization(@config)
      # iex> {:ok, %{client_id: ^client_id, resource_owner_id: ^owner_id}} = Authorizations.update([id: id], %{client_id: -1, owner_id: -1}, @config)
  """
  @spec update(Authorization.t() | keyword(), map, Charon.Config.t()) ::
          {:ok, Authorization.t()} | {:error, Changeset.t()}
  def update(authorization = %Authorization{}, params, config) do
    authorization |> Authorization.changeset(params, config) |> @repo.update()
  end

  def update(clauses, params, config) do
    Internal.get_and_do(fn -> get_by(clauses) end, &update(&1, params, config))
  end

  @doc """
  Delete an authorization.

  ## Examples / doctests

      # authorization must exist
      iex> {:error, :not_found} = Authorizations.delete(id: -1)

      # succesfully deletes an authorization
      iex> authorization = insert_test_authorization(@config)
      iex> {:ok, _} = Authorizations.delete([id: authorization.id])
      iex> {:error, :not_found} = Authorizations.delete([id: authorization.id])
  """
  @spec delete(Authorization.t() | keyword) :: {:ok, Authorization.t()} | {:error, :not_found}
  def delete(authorization = %Authorization{}), do: @repo.delete(authorization)

  def delete(clauses) do
    Internal.get_and_do(fn -> get_by(clauses) end, &delete/1)
  end
end
