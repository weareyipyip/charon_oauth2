defmodule CharonOauth2.Models.Clients do
  @moduledoc """
  Context to manage clients
  """
  require Logger

  alias CharonOauth2.Internal
  alias CharonOauth2.Models.Client

  @doc """
  Get a single client by one or more clauses, optionally with preloads.
  Returns nil if Client cannot be found.

  Supported preloads: `#{inspect(Client.supported_preloads())}`

  ## Doctests

      iex> client = insert_test_client(@config)
      iex> %Client{} = Clients.get_by(id: client.id)
      iex> nil = Clients.get_by(id: Ecto.UUID.generate())

      # preloads things
      iex> client = insert_test_client(@config)
      iex> auth = insert_test_authorization(@config, client_id: client.id)
      iex> insert_test_grant(@config, authorization_id: auth.id)
      iex> %{owner: %{id: _}, authorizations: [_]} = Clients.get_by([id: client.id], Client.supported_preloads)
  """
  @spec get_by(keyword | map, [atom]) :: Client.t() | nil
  def get_by(clauses, preloads \\ []) do
    preloads |> Client.preload() |> Internal.get_repo().get_by(clauses)
  end

  @doc """
  Get a list of all oauth2 clients.

  Supported preloads: `#{inspect(Client.supported_preloads())}`

  ## Doctests

      iex> client = insert_test_client(@config)
      iex> [^client] = Clients.all()
  """
  @spec all([atom]) :: [Client.t()]
  def all(preloads \\ []) do
    preloads |> Client.preload() |> Internal.get_repo().all()
  end

  @doc """
  Insert a new client.

  ## Examples / doctests

      # succesfully creates a client with a secret
      iex> user = insert_test_user()
      iex> {:ok, client} = %{owner_id: user.id} |> client_params() |> Clients.insert(@config)
      iex> %{secret: <<_::binary>>} = client

      # owner must exist
      iex> %{owner_id: -1} |> client_params() |> Clients.insert(@config) |> errors_on()
      %{owner: ["does not exist"]}

      iex> Clients.insert(%{}, @config) |> errors_on()
      %{grant_types: ["can't be blank"], name: ["can't be blank"], owner_id: ["can't be blank"], redirect_uris: ["can't be blank"], scopes: ["can't be blank"]}
  """
  @spec insert(map, Charon.Config.t()) :: {:ok, Client.t()} | {:error, Changeset.t()}
  def insert(params, config) do
    params
    |> Client.insert_only_changeset()
    |> Client.changeset(params, config)
    |> Internal.get_repo().insert()
  end

  @doc """
  Update a client.

  ## Examples / doctests

      iex> client = insert_test_client(@config)
      iex> {:ok, updated} = Clients.update(client, %{secret: "new!"}, @config)
      iex> false = updated.secret == client.secret

      # secret is randomly generated on update
      iex> client = insert_test_client(@config)
      iex> {:ok, updated} = Clients.update([id: client.id], %{secret: "new!"}, @config)
      iex> false = updated.secret == client.secret
      iex> false = updated.secret == "new!"

      # scopes must be subset of configured scopes
      iex> client = insert_test_client(@config)
      iex> Clients.update([id: client.id], %{scopes: ~w(cry)}, @config) |> errors_on()
      %{scopes: ["must be subset of read, write"]}

      # id and owner id can't be updated
      iex> %{id: id, owner_id: owner_id} = insert_test_client(@config)
      iex> {:ok, %{id: ^id, owner_id: ^owner_id}} = Clients.update([id: id], %{id: Ecto.UUID.generate(), owner_id: -1}, @config)
  """
  @spec update(Client.t() | keyword(), map, Charon.Config.t()) ::
          {:ok, Client.t()} | {:error, Changeset.t()}
  def update(client = %Client{}, params, config) do
    client |> Client.changeset(params, config) |> Internal.get_repo().update()
  end

  def update(clauses, params, config) do
    Internal.get_and_do(fn -> get_by(clauses) end, &update(&1, params, config))
  end

  @doc """
  Delete a client.

  ## Examples / doctests

      # client must exist
      iex> {:error, :not_found} = Clients.delete(id: Ecto.UUID.generate())

      # succesfully deletes a client
      iex> client = insert_test_client(@config)
      iex> {:ok, _} = Clients.delete([id: client.id])
      iex> {:error, :not_found} = Clients.delete([id: client.id])
  """
  @spec delete(Client.t() | keyword) :: {:ok, Client.t()} | {:error, :not_found}
  def delete(client = %Client{}), do: Internal.get_repo().delete(client)

  def delete(clauses) do
    Internal.get_and_do(fn -> get_by(clauses) end, &delete/1)
  end
end
