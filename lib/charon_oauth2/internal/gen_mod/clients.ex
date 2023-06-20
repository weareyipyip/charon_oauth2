defmodule CharonOauth2.Internal.GenMod.Clients do
  @moduledoc false

  def generate(schemas_and_contexts, repo) do
    quote location: :keep,
          generated: true,
          bind_quoted: [repo: repo, schemas_and_contexts: schemas_and_contexts] do
      @moduledoc """
      Context to manage clients
      """
      alias CharonOauth2.Internal
      alias Ecto.Changeset
      import Ecto.Query, only: [where: 3, limit: 2, offset: 2, order_by: 2]
      import Internal

      @client_schema schemas_and_contexts.client
      @repo repo

      @doc """
      Get a single client by one or more clauses, optionally with preloads.
      Returns nil if Client cannot be found.

      ## Doctests

          iex> client = insert_test_client!(owner_id: insert_test_user().id)
          iex> %Client{} = Clients.get_by(id: client.id)
          iex> nil = Clients.get_by(id: Ecto.UUID.generate())

          # preloads things
          iex> client = insert_test_client!(owner_id: insert_test_user().id)
          iex> auth = insert_test_authorization!(resource_owner_id: insert_test_user().id, client_id: client.id)
          iex> insert_test_grant!(authorization_id: auth.id)
          iex> %{owner: %{id: _}, authorizations: [_]} = Clients.get_by([id: client.id], Client.supported_preloads)
      """
      @spec get_by(keyword | map, [@client_schema.resolvable]) :: @client_schema.t() | nil
      def get_by(clauses, preloads \\ []) do
        preloads |> @client_schema.preload() |> @repo.get_by(clauses)
      end

      @doc """
      Get a list of all oauth2 clients.

      ## Doctests

          iex> client = insert_test_client!(owner_id: insert_test_user().id)
          iex> [^client] = Clients.all()

          # can be filtered
          iex> client = insert_test_client!(owner_id: insert_test_user().id)
          iex> [^client] = Clients.all(%{owner_id: client.owner_id})
          iex> [^client] = Clients.all(%{grant_types: "authorization_code"})
          iex> [] = Clients.all(%{owner_id: client.owner_id + 1})
      """
      @spec all(%{required(atom) => any}, [@client_schema.resolvable]) :: [@client_schema.t()]
      def all(filters \\ %{}, preloads \\ []) do
        base_query = @client_schema.preload(preloads)

        filters
        |> Enum.reduce(base_query, fn
          {:id, v}, q -> where(q, [c], c.id == ^v)
          {:name, v}, q -> where(q, [c], c.name == ^v)
          {:client_type, v}, q -> where(q, [c], c.client_type == ^v)
          {:owner_id, v}, q -> where(q, [c], c.owner_id == ^v)
          {:scope, v}, q -> where(q, [c], set_contains_any(c.scope, [v]))
          {:grant_types, v}, q -> where(q, [c], set_contains_any(c.grant_types, [v]))
          {:redirect_uris, v}, q -> where(q, [c], set_contains_any(c.redirect_uris, [v]))
          {:limit, v}, q -> limit(q, ^v)
          {:offset, v}, q -> offset(q, ^v)
          {:order_by, v}, q -> order_by(q, ^v)
          {k, _v}, _ -> raise "can't filter client query by #{k}"
        end)
        |> @repo.all()
      end

      @doc """
      Insert a new client.

      ## Examples / doctests

          # succesfully creates a client with a secret
          iex> user = insert_test_user()
          iex> {:ok, client} = insert_test_client(owner_id: user.id)
          iex> %{secret: <<_::binary>>} = client

          # owner must exist
          iex> insert_test_client(owner_id: -1) |> errors_on()
          %{owner: ["does not exist"]}

          iex> Clients.insert(%{}) |> errors_on()
          %{grant_types: ["can't be blank"], name: ["can't be blank"], owner_id: ["can't be blank"], redirect_uris: ["can't be blank"], scope: ["can't be blank"]}
      """
      @spec insert(map) :: {:ok, @client_schema.t()} | {:error, Changeset.t()}
      def insert(params) do
        params
        |> @client_schema.insert_only_changeset()
        |> @client_schema.changeset(params)
        |> @repo.insert()
      end

      @doc """
      Update a client.

      ## Examples / doctests

          iex> client = insert_test_client!(owner_id: insert_test_user().id)
          iex> {:ok, updated} = Clients.update(client, %{secret: "new!"})
          iex> false = updated.secret == client.secret

          # secret is randomly generated on update
          iex> client = insert_test_client!(owner_id: insert_test_user().id)
          iex> {:ok, updated} = Clients.update([id: client.id], %{secret: "new!"})
          iex> false = updated.secret == client.secret
          iex> false = updated.secret == "new!"

          # scopes must be subset of configured scopes
          iex> client = insert_test_client!(owner_id: insert_test_user().id)
          iex> Clients.update([id: client.id], %{scope: ~w(cry)}) |> errors_on()
          %{scope: ["must be subset of party, read, write"]}

          # underlying authrorization scopes are reduced to client's reduced scopes
          iex> client = insert_test_client!(owner_id: insert_test_user().id, scope: ~w(read write))
          iex> authorization = insert_test_authorization!(resource_owner_id: insert_test_user().id, client_id: client.id, scope: ~w(read write))
          iex> {:ok, _} = Clients.update([id: client.id], %{scope: ~w(read)})
          iex> %{scope: ~w(read)} = Authorizations.get_by(id: authorization.id)

          # id and owner id can't be updated
          iex> %{id: id, owner_id: owner_id} = insert_test_client!(owner_id: insert_test_user().id)
          iex> {:ok, %{id: ^id, owner_id: ^owner_id}} = Clients.update([id: id], %{id: Ecto.UUID.generate(), owner_id: -1})
      """
      @spec update(@client_schema.t() | keyword() | map, map) ::
              {:ok, @client_schema.t()} | {:error, Changeset.t()} | {:error, :not_found}
      def update(client = %@client_schema{}, params) do
        client |> @client_schema.changeset(params) |> @repo.update()
      end

      def update(clauses, params) do
        get_and_do(fn -> get_by(clauses) end, &update(&1, params), @repo)
      end

      @doc """
      Delete a client.

      ## Examples / doctests

          # client must exist
          iex> {:error, :not_found} = Clients.delete(id: Ecto.UUID.generate())

          # succesfully deletes a client
          iex> client = insert_test_client!(owner_id: insert_test_user().id)
          iex> {:ok, _} = Clients.delete([id: client.id])
          iex> {:error, :not_found} = Clients.delete([id: client.id])
      """
      @spec delete(@client_schema.t() | keyword | map) ::
              {:ok, @client_schema.t()} | {:error, :not_found}
      def delete(client = %@client_schema{}), do: @repo.delete(client)

      def delete(clauses) do
        get_and_do(fn -> get_by(clauses) end, &delete/1, @repo)
      end
    end
  end
end
