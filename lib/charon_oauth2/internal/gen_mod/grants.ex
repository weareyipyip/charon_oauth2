defmodule CharonOauth2.Internal.GenMod.Grants do
  @moduledoc false

  def generate(schemas_and_contexts, repo) do
    quote location: :keep,
          generated: true,
          bind_quoted: [schemas_and_contexts: schemas_and_contexts, repo: repo] do
      @moduledoc """
      Context to manage grants
      """
      require Logger
      alias CharonOauth2.Internal
      alias Ecto.Changeset
      import Ecto.Query, only: [from: 2, where: 3, limit: 2, offset: 2, order_by: 2]
      import Internal

      @grant_schema schemas_and_contexts.grant
      @repo repo

      @doc """
      Get a single grant by one or more clauses, optionally with preloads.
      Returns nil if Grant cannot be found.

      ## Doctests

          iex> grant = insert_test_grant()
          iex> %Grant{} = Grants.get_by(id: grant.id)
          iex> nil = Grants.get_by(id: grant.id + 1)

          # preloads things
          iex> grant = insert_test_grant()
          iex> %{authorization: %{client: %{id: _}}} = Grants.get_by([id: grant.id], Grant.supported_preloads)

          # a grant can be retrieved by its code (actually by the HMAC of its code)
          iex> %{id: id, code: code} = insert_test_grant()
          iex> ^id = Grants.get_by(code: code).id
      """
      @spec get_by(keyword | map, [@grant_schema.resolvable]) :: @grant_schema.t() | nil
      def get_by(clauses, preloads \\ []) do
        preloads |> @grant_schema.preload() |> @repo.get_by(clauses)
      end

      @doc """
      Get a list of all oauth2 grants.

      ## Doctests

          iex> insert_test_grant()
          iex> [%Grant{}] = Grants.all()

          # can be filtered
          iex> grant = insert_test_grant()
          iex> [%Grant{}] = Grants.all(%{authorization_id: grant.authorization_id})
          iex> [%Grant{}] = Grants.all(%{code: grant.code})
          iex> [] = Grants.all(%{authorization_id: grant.authorization_id + 1})
      """
      @spec all(%{required(atom) => any}, [@grant_schema.resolvable]) :: [@grant_schema.t()]
      def all(filters \\ %{}, preloads \\ []) do
        base_query = @grant_schema.preload(preloads)

        filters
        |> Enum.reduce(base_query, fn
          {:id, v}, q -> where(q, [g], g.id == ^v)
          {:code, v}, q -> where(q, [g], g.code == ^v)
          {:redirect_uri, v}, q -> where(q, [g], g.redirect_uri == ^v)
          {:type, v}, q -> where(q, [g], g.type == ^v)
          {:authorization_id, v}, q -> where(q, [g], g.authorization_id == ^v)
          {:limit, v}, q -> limit(q, ^v)
          {:offset, v}, q -> offset(q, ^v)
          {:order_by, v}, q -> order_by(q, ^v)
          {k, _v}, _ -> raise "can't filter grant query by #{k}"
        end)
        |> @repo.all()
      end

      @doc """
      Insert a new grant

      ## Examples / doctests

          # succesfully creates a grant
          iex> {:ok, _} = insert_test_grant()

          iex> Grants.insert(%{}) |> errors_on()
          %{authorization_id: ["can't be blank"], type: ["can't be blank"], resource_owner_id: ["can't be blank"]}

          # authorization must exist
          iex> insert_test_grant(authorization_id: -1) |> errors_on()
          %{authorization: ["does not exist"]}

          # resource owner must exist and must match the authorization's owner
          iex> insert_test_grant(resource_owner_id: -1) |> errors_on()
          %{authorization_id: ["belongs to other resource owner"]}

          # type must be one of client grant_type's
          iex> client = insert_test_client!(grant_types: ~w(refresh_token))
          iex> authorization = insert_test_authorization!(client_id: client.id)
          iex> insert_test_grant(authorization_id: authorization.id) |> errors_on()
          %{type: ["not supported by client"]}

          # redirect_uri must be one of client redirect_uri's
          iex> insert_test_grant(redirect_uri: "https://boom") |> errors_on()
          %{redirect_uri: ["does not match client"]}

          # redirect_uri is required if client has multiple uris set
          iex> client = insert_test_client!(redirect_uris: ~w(https://a https://b))
          iex> authorization = insert_test_authorization!(client_id: client.id)
          iex> insert_test_grant(authorization_id: authorization.id, redirect_uri: nil) |> errors_on()
          %{redirect_uri: ["can't be blank"]}
          iex> insert_test_grant(authorization_id: authorization.id, redirect_uri: "https://c") |> errors_on()
          %{redirect_uri: ["does not match client"]}
      """
      @spec insert(map) :: {:ok, @grant_schema.t()} | {:error, Changeset.t()}
      def insert(params), do: params |> @grant_schema.insert_only_changeset() |> @repo.insert()

      @doc """
      Delete a grant.

      ## Examples / doctests

          # grant must exist
          iex> {:error, :not_found} = Grants.delete(id: -1)

          # succesfully deletes a grant
          iex> grant = insert_test_grant!()
          iex> {:ok, _} = Grants.delete([id: grant.id])
          iex> {:error, :not_found} = Grants.delete([id: grant.id])
      """
      @spec delete(@grant_schema.t() | keyword | map) ::
              {:ok, @grant_schema.t()} | {:error, :not_found}
      def delete(grant = %@grant_schema{}), do: @repo.delete(grant)

      def delete(clauses) do
        get_and_do(fn -> get_by(clauses) end, &delete/1, @repo)
      end

      @doc """
      Delete all grants older than the configured `grant_ttl`.

      ## Examples / doctests

          iex> valid = insert_test_grant()
          iex> expired = insert_test_grant()
          iex> past = DateTime.utc_now() |> DateTime.add(-10)
          iex> from(t in Grant, where: t.id == ^expired.id) |> Repo.update_all(set: [expires_at: past])
          iex> Grants.delete_expired()
          iex> valid_id = valid.id
          iex> [%{id: ^valid_id}] = Grants.all()
      """
      @spec delete_expired() :: {integer, nil}
      def delete_expired() do
        from(g in @grant_schema, where: g.expires_at < ago(0, "second"))
        |> @repo.delete_all()
        |> tap(fn {n, _} -> Logger.info("Deleted #{n} expired oauth2_grants") end)
      end
    end
  end
end
