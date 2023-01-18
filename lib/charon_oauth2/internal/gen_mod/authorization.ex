defmodule CharonOauth2.Internal.GenMod.Authorization do
  @moduledoc false

  def gen_dummy(config) do
    quote generated: true do
      use Ecto.Schema
      alias CharonOauth2.Internal

      @config unquote(config)
      @mod_config Internal.get_module_config(@config)

      schema "fix warnings" do
        field :client_id, :integer

        field :resource_owner_id,
              Internal.column_type_to_ecto_type(@mod_config.resource_owner_id_type)
      end
    end
  end

  def generate(%{grant: grant_schema, client: client_schema}, config) do
    quote generated: true do
      @moduledoc """
      An authorization represents the permission granted by a resource owner (usually a user)
      to an application to act on their behalf within certain limits (determined by scopes).
      """
      alias Ecto.{Query, Changeset, Schema}
      use Schema
      import Changeset
      import Query, except: [preload: 2, preload: 3]
      alias CharonOauth2.Types.SeparatedStringMapSet
      alias CharonOauth2.Internal
      import Internal

      @config unquote(config)
      @mod_config Internal.get_module_config(@config)
      @grant_schema unquote(grant_schema)
      @client_schema unquote(client_schema)
      @res_owner_schema @mod_config.resource_owner_schema
      @app_scopes @mod_config.scopes |> MapSet.new()

      @type t :: %__MODULE__{}
      @typedoc "Bindings / preloads that can be used with `resolve_binding/2` and `preload/2`"
      @type resolvable ::
              :resource_owner
              | :resource_owner_grants
              | :client
              | :client_owner
              | :grants
              | :grants_resource_owner

      schema @mod_config.authorizations_table do
        field(:scope, SeparatedStringMapSet, pattern: [",", " "])

        belongs_to(:resource_owner, @res_owner_schema,
          references: @mod_config.resource_owner_id_column,
          type: Internal.column_type_to_ecto_type(@mod_config.resource_owner_id_type)
        )

        belongs_to(:client, @client_schema, type: Ecto.UUID)
        has_many(:grants, @grant_schema)

        timestamps(type: :utc_datetime)
      end

      @doc """
      Basic changeset.
      """
      @spec changeset(__MODULE__.t() | Changeset.t(), map()) :: Changeset.t()
      def changeset(struct_or_cs \\ %__MODULE__{}, params) do
        struct_or_cs
        |> cast(params, [:scope])
        |> validate_required([:scope])
        |> validate_mapset_contains(
          :scope,
          @app_scopes,
          "must be subset of #{Enum.join(@app_scopes, ", ")}"
        )
        |> prepare_changes(fn cs = %{data: data, changes: %{scope: scopes}} ->
          with <<client_id::binary>> <- get_field(cs, :client_id),
               client = %{scope: client_scopes} <- cs.repo.get(@client_schema, client_id),
               [] <- MapSet.difference(scopes, client_scopes) |> MapSet.to_list() do
            %{cs | data: %{data | client: client}}
          else
            nil ->
              cs

            scopes ->
              scopes = Enum.join(scopes, ", ")
              add_error(cs, :scope, "client not allowed to access scope(s): #{scopes}")
          end
        end)
      end

      @doc """
      Insert-only changeset - some things (should) never change.
      """
      @spec insert_only_changeset(__MODULE__.t() | Changeset.t(), map()) :: Changeset.t()
      def insert_only_changeset(struct_or_cs \\ %__MODULE__{}, params) do
        struct_or_cs
        |> cast(params, [:resource_owner_id, :client_id])
        |> validate_required([:resource_owner_id, :client_id])
        |> assoc_constraint(:resource_owner)
        |> assoc_constraint(:client)
        |> unique_constraint([:client_id, :resource_owner_id],
          message: "user already authorized this client"
        )
      end

      ###########
      # Queries #
      ###########

      @doc """
      Returns a new query with the current module as named binding `:charon_oauth2_authorization`.
      """
      @spec named_binding() :: Query.t()
      def named_binding() do
        from(u in __MODULE__, as: :charon_oauth2_authorization)
      end

      @doc """
      Resolve named bindings that are not present in the query by (left-)joining to the appropriate tables.
      """
      @spec resolve_binding(Query.t(), resolvable) :: Query.t()
      def resolve_binding(query, named_binding) do
        if has_named_binding?(query, named_binding) do
          query
        else
          case named_binding do
            :resource_owner ->
              join(
                query,
                :left,
                [charon_oauth2_authorization: a],
                ro in assoc(a, :resource_owner),
                as: :resource_owner
              )

            :resource_owner_grants ->
              query
              |> resolve_binding(:resource_owner)
              |> join(:left, [resource_owner: ro], g in assoc(ro, :grants),
                as: :resource_owner_grants
              )

            :client ->
              join(query, :left, [charon_oauth2_authorization: a], ro in assoc(a, :client),
                as: :client
              )

            :client_owner ->
              query
              |> resolve_binding(:client)
              |> join(:left, [client: c], o in assoc(c, :owner), as: :client_owner)

            :grants ->
              join(query, :left, [charon_oauth2_authorization: a], ro in assoc(a, :grants),
                as: :grants
              )

            :grants_resource_owner ->
              query
              |> resolve_binding(:grants)
              |> join(:left, [grants: g], ro in assoc(g, :resource_owner),
                as: :grants_resource_owner
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
          :resource_owner ->
            query
            |> resolve_binding(:resource_owner)
            |> Query.preload([resource_owner: ro], resource_owner: ro)

          :resource_owner_grants ->
            query
            |> resolve_binding(:resource_owner)
            |> Query.preload([resource_owner: ro], resource_owner: {ro, :grants})

          :client ->
            query |> resolve_binding(:client) |> Query.preload([client: c], client: c)

          :client_owner ->
            query
            |> resolve_binding(:client_owner)
            |> Query.preload([client: c, client_owner: o], client: {c, owner: o})

          :grants ->
            Query.preload(query, :grants)

          :grants_resource_owner ->
            subq =
              from(g in @grant_schema,
                left_join: ro in assoc(g, :resource_owner),
                preload: [resource_owner: ro]
              )

            Query.preload(query, grants: ^subq)
        end
      end

      def preload(query, list), do: Enum.reduce(list, query, &preload(&2, &1))

      @doc false
      # used for tests
      def supported_preloads() do
        [
          :resource_owner,
          :resource_owner_grants,
          :client,
          :client_owner,
          :grants,
          :grants_resource_owner
        ]
      end
    end
  end
end
