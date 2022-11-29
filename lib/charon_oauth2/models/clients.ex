defmodule CharonOauth2.Models.Clients do
  @moduledoc """
  Context to manage oauth2_clients
  """
  require Logger

  alias CharonOauth2.Internal
  alias CharonOauth2.Models.Client
  @repo Application.compile_env!(:charon_oauth2, :repo)

  @doc """
  Get a single oauth2_client by one or more clauses, optionally with preloads.
  Returns nil if Client cannot be found.

  ## Doctests

      iex> client = insert_test_client(@config)
      iex> ^client = Clients.get_by(id: client.id)
      iex> nil = Clients.get_by(id: Ecto.UUID.generate())
  """
  @spec get_by(keyword | map, [atom]) :: Client.t() | nil
  def get_by(clauses, preloads \\ []) do
    preloads |> Client.preload() |> @repo.get_by(clauses)
  end

  @doc """
  Get a list of all oauth2 clients.

  ## Doctests

      iex> client = insert_test_client(@config)
      iex> [^client] = Clients.all()
  """
  @spec all([atom]) :: [Client.t()]
  def all(preloads \\ []) do
    preloads |> Client.preload() |> @repo.all()
  end

  @doc """
  Insert a new oauth2_client

  ## Examples / doctests

      # succesfully creates an oauth2_client with a secret
      iex> user = insert_test_user()
      iex> {:ok, client} = %{owner_id: user.id} |> client_params() |> Clients.insert(@config)
      iex> %{secret: <<_::binary>>} = client
  """
  @spec insert(map, Charon.Config.t()) :: {:ok, Client.t()} | {:error, Changeset.t()}
  def insert(params, config) do
    params |> Client.insert_only_changeset() |> Client.changeset(params, config) |> @repo.insert()
  end

  @doc """
  Update an oauth2_client.

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
      iex> {:ok, %{id: ^id, owner_id: ^owner_id}} = Clients.update([id: id], %{id: Ecto.UUID.generate(), owner_id: insert_test_user().id}, @config)
  """
  @spec update(Client.t() | keyword(), map, Charon.Config.t()) ::
          {:ok, Client.t()} | {:error, Changeset.t()}
  def update(client = %Client{}, params, config) do
    client |> Client.changeset(params, config) |> @repo.update()
  end

  def update(clauses, params, config) do
    Internal.get_and_do(fn -> get_by(clauses) end, &update(&1, params, config))
  end

  @doc """
  Delete an oauth2_client.

  ## Examples / doctests

      # oauth2_client must exist
      iex> {:error, :not_found} = Clients.delete(id: Ecto.UUID.generate())

      # succesfully deletes an oauth2_client
      iex> client = insert_test_client(@config)
      iex> {:ok, _} = Clients.delete([id: client.id])
      iex> {:error, :not_found} = Clients.delete([id: client.id])
  """
  @spec delete(Client.t() | keyword) :: {:ok, Client.t()} | {:error, :not_found}
  def delete(client = %Client{}), do: @repo.delete(client)

  def delete(clauses) do
    Internal.get_and_do(fn -> get_by(clauses) end, &delete/1)
  end
end
