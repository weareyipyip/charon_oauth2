defmodule CharonOauth2.GenEctoMod.Authorizations do
  def generate(authorization_schema, repo) do
    quote do
      @moduledoc """
      Context to manage authorizations
      """
      require Logger

      alias CharonOauth2.Internal
      @authorization_schema unquote(authorization_schema)
      @repo unquote(repo)

      @doc """
      Get a single authorization by one or more clauses, optionally with preloads.
      Returns nil if Authorization cannot be found.

      Supported preloads: `#{inspect(@authorization_schema.supported_preloads())}`

      ## Doctests

          iex> authorization = insert_test_authorization()
          iex> %Authorization{} = Authorizations.get_by(id: authorization.id)
          iex> nil = Authorizations.get_by(id: authorization.id + 1)

          # preloads things
          iex> authorization = insert_test_authorization()
          iex> %{resource_owner: %{id: _}, client: %{id: _}} = Authorizations.get_by([id: authorization.id], Authorization.supported_preloads)
      """
      @spec get_by(keyword | map, [atom]) :: @authorization_schema.t() | nil
      def get_by(clauses, preloads \\ []) do
        preloads |> @authorization_schema.preload() |> @repo.get_by(clauses)
      end

      @doc """
      Get a list of all oauth2 authorizations.

      Supported preloads: `#{inspect(@authorization_schema.supported_preloads())}`

      ## Doctests

          iex> insert_test_authorization()
          iex> [%Authorization{}] = Authorizations.all()
      """
      @spec all([atom]) :: [@authorization_schema.t()]
      def all(preloads \\ []) do
        preloads |> @authorization_schema.preload() |> @repo.all()
      end

      @doc """
      Insert a new authorization

      ## Examples / doctests

          # succesfully creates an authorization
          iex> {:ok, _} = authorization_params() |> Authorizations.insert()

          # a user can authorize a client only once
          iex> {:ok, authorization} = authorization_params() |> Authorizations.insert()
          iex> authorization_params(client_id: authorization.client_id, resource_owner_id: authorization.resource_owner_id) |> Authorizations.insert() |> errors_on()
          %{client_id: ["user already authorized this client"]}

          # owner and client must exist
          iex> authorization_params(resource_owner_id: -1) |> Authorizations.insert() |> errors_on()
          %{resource_owner: ["does not exist"]}
          iex> authorization_params(client_id: Ecto.UUID.generate()) |> Authorizations.insert() |> errors_on()
          %{client: ["does not exist"]}

          iex> Authorizations.insert(%{}) |> errors_on()
          %{scopes: ["can't be blank"], client_id: ["can't be blank"], resource_owner_id: ["can't be blank"]}
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

      ## Examples / doctests

          # scopes must be subset of configured scopes and of client scopes
          iex> insert_test_authorization() |> Authorizations.update(%{scopes: ~w(cry)}) |> errors_on()
          %{scopes: ["must be subset of read, write"]}
          iex> insert_test_authorization() |> Authorizations.update(%{scopes: ~w(write write)}) |> errors_on()
          %{scopes: ["client not allowed to access scope(s): write"]}

          # # client and resource owner can't be updated
          # iex> %{client_id: client_id, resource_owner_id: owner_id} = insert_test_authorization()
          # iex> {:ok, %{client_id: ^client_id, resource_owner_id: ^owner_id}} = Authorizations.update([id: id], %{client_id: -1, owner_id: -1})
      """
      @spec update(@authorization_schema.t() | keyword(), map) ::
              {:ok, @authorization_schema.t()} | {:error, Changeset.t()}
      def update(authorization = %@authorization_schema{}, params) do
        authorization
        |> @authorization_schema.changeset(params)
        |> @repo.update()
      end

      def update(clauses, params) do
        Internal.get_and_do(fn -> get_by(clauses) end, &update(&1, params), @repo)
      end

      @doc """
      Delete an authorization.

      ## Examples / doctests

          # authorization must exist
          iex> {:error, :not_found} = Authorizations.delete(id: -1)

          # succesfully deletes an authorization
          iex> authorization = insert_test_authorization()
          iex> {:ok, _} = Authorizations.delete([id: authorization.id])
          iex> {:error, :not_found} = Authorizations.delete([id: authorization.id])
      """
      @spec delete(@authorization_schema.t() | keyword) ::
              {:ok, @authorization_schema.t()} | {:error, :not_found}
      def delete(authorization = %@authorization_schema{}), do: @repo.delete(authorization)

      def delete(clauses) do
        Internal.get_and_do(fn -> get_by(clauses) end, &delete/1, @repo)
      end
    end
  end
end
