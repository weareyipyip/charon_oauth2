defmodule CharonOauth2.Internal.GenMod.Authorizations do
  @moduledoc false

  def generate(schemas_and_contexts, repo) do
    quote location: :keep,
          generated: true,
          bind_quoted: [schemas_and_contexts: schemas_and_contexts, repo: repo] do
      @moduledoc """
      Context to manage authorizations
      """
      require Logger
      import Ecto.Query, only: [where: 3, limit: 2, offset: 2, order_by: 2]
      alias Ecto.Changeset
      alias CharonOauth2.Internal
      import Internal

      @authorization_schema schemas_and_contexts.authorization
      @repo repo

      @doc """
      Get a single authorization by one or more clauses, optionally with preloads.
      Returns nil if Authorization cannot be found.

      ## Doctests

          iex> authorization = insert_test_authorization!(resource_owner_id: insert_test_user().id)
          iex> %Authorization{} = Authorizations.get_by(id: authorization.id)
          iex> nil = Authorizations.get_by(id: authorization.id + 1)

          # preloads things
          iex> authorization = insert_test_authorization!(resource_owner_id: insert_test_user().id)
          iex> %{resource_owner: %{id: _}, client: %{id: _}} = Authorizations.get_by([id: authorization.id], Authorization.supported_preloads)
      """
      @spec get_by(keyword | map, [@authorization_schema.resolvable]) ::
              @authorization_schema.t() | nil
      def get_by(clauses, preloads \\ []) do
        preloads |> @authorization_schema.preload() |> @repo.get_by(clauses)
      end

      @doc """
      Get a list of all oauth2 authorizations.

      ## Doctests

          iex> insert_test_authorization!(resource_owner_id: insert_test_user().id)
          iex> [%Authorization{}] = Authorizations.all()

          # can be filtered
          iex> authorization = insert_test_authorization!(resource_owner_id: insert_test_user().id)
          iex> [%Authorization{}] = Authorizations.all(%{resource_owner_id: authorization.resource_owner_id})
          iex> [%Authorization{}] = Authorizations.all(%{scope: authorization.scope |> List.first()})
          iex> [] = Authorizations.all(%{resource_owner_id: authorization.resource_owner_id + 1})
      """
      @spec all(%{required(atom) => any}, [@authorization_schema.resolvable]) ::
              [@authorization_schema.t()]
      def all(filters \\ %{}, preloads \\ []) do
        base_query = @authorization_schema.preload(preloads)

        filters
        |> Enum.reduce(base_query, fn
          {:id, v}, q -> where(q, [a], a.id == ^v)
          {:client_id, v}, q -> where(q, [a], a.client_id == ^v)
          {:resource_owner_id, v}, q -> where(q, [a], a.resource_owner_id == ^v)
          {:scope, v}, q -> where(q, [a], set_contains_any(a.scope, [v]))
          {:limit, v}, q -> limit(q, ^v)
          {:offset, v}, q -> offset(q, ^v)
          {:order_by, v}, q -> order_by(q, ^v)
          {k, _v}, _ -> raise "can't filter authorization query by #{k}"
        end)
        |> @repo.all()
      end

      @doc """
      Insert a new authorization

      ## Examples / doctests

          # succesfully creates an authorization
          iex> {:ok, _} = insert_test_authorization(resource_owner_id: insert_test_user().id)

          # a user can authorize a client only once
          iex> {:ok, authorization} = insert_test_authorization(resource_owner_id: insert_test_user().id)
          iex> insert_test_authorization(resource_owner_id: authorization.resource_owner_id, client_id: authorization.client_id) |> errors_on()
          %{client_id: ["user already authorized this client"]}

          # owner and client must exist
          iex> insert_test_authorization(resource_owner_id: -1, client_id: insert_test_client!(owner_id: insert_test_user().id).id) |> errors_on()
          %{resource_owner: ["does not exist"]}
          iex> insert_test_authorization(resource_owner_id: insert_test_user().id, client_id: Ecto.UUID.generate()) |> errors_on()
          %{client: ["does not exist"]}

          iex> Authorizations.insert(%{}) |> errors_on()
          %{scope: ["can't be blank"], client_id: ["can't be blank"], resource_owner_id: ["can't be blank"]}
      """
      @spec insert(map) :: {:ok, @authorization_schema.t()} | {:error, Changeset.t()}
      def insert(params) do
        params
        |> @authorization_schema.insert_only_changeset()
        |> @authorization_schema.changeset(params)
        |> @repo.insert()
      end

      @doc """
      Update an authorization.

      # TODO: fix ~(write write) test by implementing overrides
      ## Examples / doctests

          # scopes must be subset of configured scopes and of client scopes
          iex> insert_test_authorization!(resource_owner_id: insert_test_user().id) |> Authorizations.update(%{scope: ~w(cry)}) |> errors_on()
          %{scope: ["must be subset of party, read, write"]}
          iex> insert_test_authorization!(resource_owner_id: insert_test_user().id) |> Authorizations.update(%{scope: ~w(write write)}) |> errors_on()
          %{scope: ["client not allowed to access scope(s): write"]}

          # client and resource owner can't be updated
          iex> %{id: id, client_id: client_id, resource_owner_id: owner_id} = insert_test_authorization!(resource_owner_id: insert_test_user().id)
          iex> {:ok, %{client_id: ^client_id, resource_owner_id: ^owner_id}} = Authorizations.update([id: id], %{client_id: -1, owner_id: -1})
      """
      @spec update(@authorization_schema.t() | keyword() | map(), map) ::
              {:ok, @authorization_schema.t()} | {:error, Changeset.t()} | {:error, :not_found}
      def update(authorization = %@authorization_schema{}, params) do
        authorization
        |> @authorization_schema.changeset(params)
        |> @repo.update()
      end

      def update(clauses, params) do
        get_and_do(fn -> get_by(clauses) end, &update(&1, params), @repo)
      end

      @doc """
      Delete an authorization.

      ## Examples / doctests

          # authorization must exist
          iex> {:error, :not_found} = Authorizations.delete(id: -1)

          # succesfully deletes an authorization
          iex> authorization = insert_test_authorization!(resource_owner_id: insert_test_user().id)
          iex> {:ok, _} = Authorizations.delete([id: authorization.id])
          iex> {:error, :not_found} = Authorizations.delete([id: authorization.id])
      """
      @spec delete(@authorization_schema.t() | keyword | map) ::
              {:ok, @authorization_schema.t()} | {:error, :not_found}
      def delete(authorization = %@authorization_schema{}), do: @repo.delete(authorization)

      def delete(clauses) do
        get_and_do(fn -> get_by(clauses) end, &delete/1, @repo)
      end
    end
  end
end
