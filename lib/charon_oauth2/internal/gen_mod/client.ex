defmodule CharonOauth2.Internal.GenMod.Client do
  @moduledoc false

  def generate(%{authorization: authorization_schema, grant: grant_schema}, config) do
    quote generated: true do
      @moduledoc """
      An Oauth2 (third-party) client application.

      Fields `:scope`, `:grant_types` and `:redirect_uris` are guaranteed to be ordsets (`:ordsets`).
      """
      alias Ecto.{Query, Changeset, Schema}
      use Schema
      import Changeset
      import Query, except: [preload: 2, preload: 3]
      alias CharonOauth2.Types.{SeparatedStringOrdset, Encrypted}
      alias CharonOauth2.Internal
      import CharonOauth2.Internal
      alias Charon.Internal, as: CharonInternal

      @type t :: %__MODULE__{}
      @typedoc "Bindings / preloads that can be used with `resolve_binding/2` and `preload/2`"
      @type resolvable ::
              :owner
              | :authorizations
              | :authorizations_resource_owner
              | :authorizations_grants
              | :authorizations_grants_resource_owner

      @config unquote(config)
      @mod_config Internal.get_module_config(@config)
      @auth_schema unquote(authorization_schema)
      @grant_schema unquote(grant_schema)
      @res_owner_schema @mod_config.resource_owner_schema
      @app_scopes @mod_config.scopes |> Map.keys() |> :ordsets.from_list()

      @client_types ~w(confidential public)
      @grant_types ~w(authorization_code refresh_token) |> :ordsets.from_list()
      @secret_bytesize 48
      @autogen_secret {CharonInternal, :random_url_encoded, [@secret_bytesize]}

      @primary_key {:id, Ecto.UUID, autogenerate: true}
      schema @mod_config.client_table do
        field(:name, :string)
        field(:secret, Encrypted, redact: true, autogenerate: @autogen_secret, config: @config)
        field(:redirect_uris, SeparatedStringOrdset, pattern: ",")
        field(:scope, SeparatedStringOrdset, pattern: [",", " "])
        field(:grant_types, SeparatedStringOrdset, pattern: ",")
        field(:client_type, :string, default: "confidential")
        field(:description, :string)

        has_many(:authorizations, @auth_schema)

        belongs_to(:owner, @res_owner_schema,
          references: @mod_config.resource_owner_id_column,
          type: Internal.column_type_to_ecto_type(@mod_config.resource_owner_id_type)
        )

        timestamps(type: :utc_datetime)
      end

      @doc """
      Basic changeset.
      """
      @spec changeset(__MODULE__.t() | Changeset.t(), map()) ::
              Changeset.t()
      def changeset(struct_or_cs \\ %__MODULE__{}, params) do
        struct_or_cs
        |> cast(params, [
          :name,
          :redirect_uris,
          :scope,
          :grant_types,
          :client_type,
          :secret,
          :description
        ])
        |> validate_required([:name, :redirect_uris, :scope, :grant_types, :client_type])
        |> validate_inclusion(:client_type, @client_types,
          message: "must be one of: #{Enum.join(@client_types, ", ")}"
        )
        |> validate_sub_ordset(
          :grant_types,
          @grant_types,
          "must be subset of #{Enum.join(@grant_types, ", ")}"
        )
        |> validate_sub_ordset(
          :scope,
          @app_scopes,
          "must be subset of #{Enum.join(@app_scopes, ", ")}"
        )
        |> prepare_changes(fn
          cs = %{data: %{id: id, scope: current_scopes}, changes: %{scope: scopes}}
          when not is_nil(id) ->
            if [] != (removed_scopes = :ordsets.subtract(current_scopes, scopes)) do
              from(a in @auth_schema, where: a.client_id == ^id, select: {a.id, a.scope})
              |> cs.repo.all()
              |> Enum.each(fn {auth_id, auth_scopes} ->
                auth_scopes = :ordsets.subtract(auth_scopes, removed_scopes)

                {1, _} =
                  from(a in @auth_schema, where: a.id == ^auth_id)
                  |> cs.repo.update_all(set: [scope: auth_scopes])
              end)
            end

            cs

          cs ->
            cs
        end)
        |> validate_change(:redirect_uris, fn _fld, uris ->
          # redirect uri must be valid, https and may not contain fragments, according to the spec
          # https://datatracker.ietf.org/doc/html/rfc6749#section-3.1.2
          if invalid_uri =
               Enum.find(uris, &(!match?({:ok, %{fragment: nil, scheme: "https"}}, URI.new(&1)))) do
            [redirect_uris: "invalid uri: #{invalid_uri}"]
          else
            []
          end
        end)
        # always randomly (re)generate the secret
        |> update_change(:secret, fn _ -> CharonInternal.random_url_encoded(@secret_bytesize) end)
        |> validate_length(:description, max: 250)
      end

      @doc """
      Insert-only changeset.
      """
      @spec insert_only_changeset(__MODULE__.t() | Changeset.t(), map()) :: Changeset.t()
      def insert_only_changeset(struct_or_cs \\ %__MODULE__{}, params) do
        struct_or_cs
        |> cast(params, [:id, :owner_id])
        |> validate_required([:owner_id])
        |> unique_constraint(:id, name: "charon_oauth2_clients_pkey")
        |> assoc_constraint(:owner)
      end

      ###########
      # Queries #
      ###########

      @doc """
      Returns a new query with the current module as named binding `:charon_oauth2_client`.
      """
      @spec named_binding() :: Query.t()
      def named_binding() do
        from(u in __MODULE__, as: :charon_oauth2_client)
      end

      @doc """
      Resolve named bindings that are not present in the query by (left-)joining to the appropriate tables.
      """
      @spec resolve_binding(Query.t(), resolvable()) :: Query.t()
      def resolve_binding(query, named_binding) do
        if has_named_binding?(query, named_binding) do
          query
        else
          case named_binding do
            :owner ->
              join(query, :left, [charon_oauth2_client: c], ro in assoc(c, :owner), as: :owner)

            :authorizations ->
              query
              |> join(:left, [charon_oauth2_client: c], a in assoc(c, :authorizations),
                as: :authorizations
              )

            :authorizations_resource_owner ->
              query
              |> resolve_binding(:authorizations)
              |> join(:left, [authorizations: a], ro in assoc(a, :resource_owner),
                as: :authorizations_resource_owner
              )

            :authorizations_grants ->
              query
              |> resolve_binding(:authorizations)
              |> join(:left, [authorizations: a], g in assoc(a, :grants),
                as: :authorizations_grants
              )

            :authorizations_grants_resource_owner ->
              query
              |> resolve_binding(:authorizations_grants)
              |> join(:left, [authorizations_grants: g], ro in assoc(g, :resource_owner),
                as: :authorizations_grants_resource_owner
              )
          end
        end
      end

      @doc """
      Preload named bindings. Automatically joins using `resolve_binding/2`.
      """
      @spec preload(Query.t(), resolvable | [resolvable]) :: Query.t()
      def preload(query \\ named_binding(), named_binding_or_bindings)

      def preload(query, named_binding) when is_atom(named_binding) do
        case named_binding do
          :owner ->
            query |> resolve_binding(:owner) |> Query.preload([owner: o], owner: o)

          :authorizations ->
            Query.preload(query, :authorizations)

          :authorizations_resource_owner ->
            subq =
              from(a in @auth_schema,
                left_join: ro in assoc(a, :resource_owner),
                preload: [resource_owner: ro]
              )

            Query.preload(query, authorizations: ^subq)

          :authorizations_grants ->
            Query.preload(query, authorizations: [:grants])

          :authorizations_grants_resource_owner ->
            subq =
              from(g in @grant_schema,
                left_join: ro in assoc(g, :resource_owner),
                preload: [resource_owner: ro]
              )

            Query.preload(query, authorizations: [grants: ^subq])
        end
      end

      def preload(query, list), do: Enum.reduce(list, query, &preload(&2, &1))

      @doc false
      # used for tests
      def supported_preloads() do
        [
          :owner,
          :authorizations,
          :authorizations_resource_owner,
          :authorizations_grants,
          :authorizations_grants_resource_owner
        ]
      end
    end
  end
end
