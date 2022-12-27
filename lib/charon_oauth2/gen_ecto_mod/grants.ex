defmodule CharonOauth2.GenEctoMod.Grants do
  @moduledoc "Generate an app's Grants module."

  def generate(grant_schema, repo) do
    quote do
      @moduledoc """
      Context to manage grants
      """
      require Logger

      alias CharonOauth2.Internal
      import Ecto.Query, only: [from: 2]

      @grant_schema unquote(grant_schema)
      @repo unquote(repo)

      @doc """
      Get a single grant by one or more clauses, optionally with preloads.
      Returns nil if Grant cannot be found.

      Supported preloads: `#{inspect(@grant_schema.supported_preloads())}`

      ## Doctests

          iex> grant = insert_test_grant(@config)
          iex> %Grant{} = Grants.get_by(id: grant.id)
          iex> nil = Grants.get_by(id: grant.id + 1)

          # preloads things
          iex> grant = insert_test_grant(@config)
          iex> %{authorization: %{client: %{id: _}}} = Grants.get_by([id: grant.id], Grant.supported_preloads)

          # a grant can be retrieved by its code (actually by the HMAC of its code)
          iex> %{id: id, code: code} = insert_test_grant(@config)
          iex> ^id = Grants.get_by(code: code).id
      """
      @spec get_by(keyword | map, [atom]) :: @grant_schema.t() | nil
      def get_by(clauses, preloads \\ []) do
        preloads |> @grant_schema.preload() |> @repo.get_by(clauses)
      end

      @doc """
      Get a list of all oauth2 grants.

      Supported preloads: `#{inspect(@grant_schema.supported_preloads())}`

      ## Doctests

          iex> insert_test_grant(@config)
          iex> [%Grant{}] = Grants.all()
      """
      @spec all([atom]) :: [@grant_schema.t()]
      def all(preloads \\ []) do
        preloads |> @grant_schema.preload() |> @repo.all()
      end

      @doc """
      Insert a new grant

      ## Examples / doctests

          # succesfully creates a grant
          iex> {:ok, _} = grant_params(@config) |> Grants.insert(@config)

          iex> Grants.insert(%{}, @config) |> errors_on()
          %{authorization_id: ["can't be blank"], redirect_uri: ["can't be blank"], type: ["can't be blank"]}

          # authorization must exist
          iex> grant_params(@config, authorization_id: -1) |> Grants.insert(@config) |> errors_on()
          %{authorization: ["does not exist"]}

          # type must be one of client grant_type's
          iex> client = insert_test_client(@config, grant_types: ~w(refresh_token))
          iex> authorization = insert_test_authorization(@config, client_id: client.id)
          iex> grant_params(@config, authorization_id: authorization.id) |> Grants.insert(@config) |> errors_on()
          %{type: ["not supported by client"]}

          # redirect_uri must be one of client redirect_uri's
          iex> grant_params(@config, redirect_uri: "https://boom") |> Grants.insert(@config) |> errors_on()
          %{redirect_uri: ["does not match client"]}
      """
      @spec insert(map, Charon.Config.t()) ::
              {:ok, @grant_schema.t()} | {:error, Changeset.t()}
      def insert(params, config) do
        params |> @grant_schema.insert_only_changeset(config) |> @repo.insert()
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
      @spec delete(@grant_schema.t() | keyword) ::
              {:ok, @grant_schema.t()} | {:error, :not_found}
      def delete(grant = %@grant_schema{}), do: @repo.delete(grant)

      def delete(clauses) do
        Internal.get_and_do(fn -> get_by(clauses) end, &delete/1, @repo)
      end

      @doc """
      Delete all grants older than the configured `grant_ttl`.

      ## Examples / doctests

          iex> valid = insert_test_grant(@config)
          iex> expired = insert_test_grant(@config)
          iex> past = DateTime.from_unix!(System.os_time(:second) - 10)
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
