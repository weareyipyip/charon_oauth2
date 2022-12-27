defmodule CharonOauth2.GenEctoMod.Authorization do
  @moduledoc "Generate an app's Authorization module."

  def gen_dummy() do
    quote do
      use Ecto.Schema

      schema "fix warnings" do
        field :client_id, :integer
      end
    end
  end

  def generate(resource_owner_schema, client_schema, grant_schema, config) do
    quote generated: true do
      @moduledoc """
      An authorization represents the permission granted by a resource owner (usually a user)
      to an application to act on their behalf within certain limits (determined by scopes).
      """
      use Ecto.Schema
      import Ecto.Changeset
      import Ecto.Query, except: [preload: 2, preload: 3]
      alias Ecto.Query
      alias CharonOauth2.Types.SeparatedString
      alias CharonOauth2.Internal
      import Internal

      @config unquote(config)
      @mod_config Internal.get_module_config(@config)
      @grant_schema unquote(grant_schema)
      @client_schema unquote(client_schema)
      @res_owner_schema unquote(resource_owner_schema)

      @type t :: %__MODULE__{}

      schema @mod_config.authorization_table do
        field(:scopes, SeparatedString, pattern: ",")

        belongs_to(:resource_owner, @res_owner_schema)
        belongs_to(:client, @client_schema, type: :binary_id)
        has_many(:grants, @grant_schema)

        timestamps(type: :utc_datetime)
      end

      @doc """
      Basic changeset.
      """
      @spec changeset(__MODULE__.t() | Changeset.t(), map(), Charon.Config.t()) :: Changeset.t()
      def changeset(struct_or_cs \\ %__MODULE__{}, params, config) do
        config = get_module_config(config)

        struct_or_cs
        |> cast(params, [:scopes])
        |> validate_required([:scopes])
        |> multifield_apply([:scopes], &to_set/2)
        |> validate_subset(:scopes, config.scopes,
          message: "must be subset of #{Enum.join(config.scopes, ", ")}"
        )
        |> prepare_changes(fn cs = %{data: data, changes: %{scopes: scopes}} ->
          with <<client_id::binary>> <- get_field(cs, :client_id),
               client = %{scopes: client_scopes} <- cs.repo.get(@client_schema, client_id),
               [] <- scopes -- client_scopes do
            %{cs | data: %{data | client: client}}
          else
            nil ->
              cs

            scopes ->
              scopes = Enum.join(scopes, ", ")
              add_error(cs, :scopes, "client not allowed to access scope(s): #{scopes}")
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
      @spec resolve_binding(Query.t(), atom()) :: Query.t()
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

            :client ->
              join(query, :left, [charon_oauth2_authorization: a], ro in assoc(a, :client),
                as: :client
              )

            :grants ->
              join(query, :left, [charon_oauth2_authorization: a], ro in assoc(a, :grants),
                as: :grants
              )
          end
        end
      end

      @doc """
      Preload named bindings. Automatically joins using `resolve_binding/2`.
      """
      @spec preload(Query.t(), atom | [atom]) :: Query.t()
      def preload(query \\ named_binding(), named_binding_or_bindings)

      def preload(query, named_binding) when is_atom(named_binding) do
        case named_binding do
          :resource_owner ->
            query
            |> resolve_binding(:resource_owner)
            |> Query.preload([resource_owner: ro], resource_owner: ro)

          :client ->
            query |> resolve_binding(:client) |> Query.preload([client: c], client: c)

          :grants ->
            Query.preload(query, :grants)
        end
      end

      def preload(query, list), do: Enum.reduce(list, query, &preload(&2, &1))

      @doc false
      def supported_preloads(), do: ~w(resource_owner client grants)a
    end
  end
end
