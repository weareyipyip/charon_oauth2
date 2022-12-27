defmodule CharonOauth2.GenEctoMod.Client do
  @moduledoc "Generate an app's Client module."

  def generate(authorization_schema, config) do
    quote generated: true do
      @moduledoc """
      An Oauth2 (third-party) client application.
      """
      use Ecto.Schema
      import Ecto.Changeset
      import Ecto.Query, except: [preload: 2, preload: 3]
      alias Ecto.Query
      alias CharonOauth2.Types.{SeparatedString, Encrypted}
      alias CharonOauth2.Internal
      import CharonOauth2.Internal
      alias Charon.Internal, as: CharonInternal

      @type t :: %__MODULE__{}

      @config unquote(config)
      @mod_config Internal.get_module_config(@config)
      @auth_schema unquote(authorization_schema)
      @res_owner_schema @mod_config.resource_owner_schema

      @client_types ~w(confidential public)
      @grant_types ~w(authorization_code refresh_token)
      @autogen_secret {CharonInternal, :random_url_encoded, [32]}

      @primary_key {:id, :binary_id, autogenerate: true}
      schema @mod_config.client_table do
        field(:name, :string)
        field(:secret, Encrypted, redact: true, autogenerate: @autogen_secret, config: @config)
        field(:redirect_uris, SeparatedString, pattern: ",")
        field(:scopes, SeparatedString, pattern: ",")
        field(:grant_types, SeparatedString, pattern: ",")
        field(:client_type, :string, default: "confidential")

        has_many(:authorizations, @auth_schema)
        belongs_to(:owner, @res_owner_schema)

        timestamps(type: :utc_datetime)
      end

      @doc """
      Basic changeset.
      """
      @spec changeset(__MODULE__.t() | Changeset.t(), map(), Charon.Config.t()) ::
              Changeset.t()
      def changeset(struct_or_cs \\ %__MODULE__{}, params, config) do
        config = get_module_config(config)

        struct_or_cs
        |> cast(params, [:name, :redirect_uris, :scopes, :grant_types, :client_type, :secret])
        |> validate_required([:name, :redirect_uris, :scopes, :grant_types, :client_type])
        |> multifield_apply([:redirect_uris, :scopes, :grant_types], &to_set/2)
        |> validate_inclusion(:client_type, @client_types,
          message: "must be one of: #{Enum.join(@client_types, ", ")}"
        )
        |> validate_subset(:grant_types, @grant_types,
          message: "must be subset of #{Enum.join(@grant_types, ", ")}"
        )
        |> validate_subset(:scopes, config.scopes,
          message: "must be subset of #{Enum.join(config.scopes, ", ")}"
        )
        |> validate_change(:redirect_uris, fn _fld, uris ->
          if invalid_uri = Enum.find(uris, &(!match?({:ok, _}, URI.new(&1)))) do
            [redirect_uris: "invalid uri: #{invalid_uri}"]
          else
            []
          end
        end)
        # always randomly (re)generate the secret
        |> update_change(:secret, fn _ -> CharonInternal.random_url_encoded(32) end)
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
      @spec resolve_binding(Query.t(), atom()) :: Query.t()
      def resolve_binding(query, named_binding) do
        if has_named_binding?(query, named_binding) do
          query
        else
          case named_binding do
            :owner ->
              join(query, :left, [charon_oauth2_client: c], ro in assoc(c, :owner), as: :owner)
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
          :owner ->
            query |> resolve_binding(:owner) |> Query.preload([owner: o], owner: o)

          :authorizations ->
            Query.preload(query, :authorizations)

          :authorizations_grants ->
            Query.preload(query, authorizations: [:grants])
        end
      end

      def preload(query, list), do: Enum.reduce(list, query, &preload(&2, &1))

      @doc false
      def supported_preloads(), do: ~w(owner authorizations authorizations_grants)a
    end
  end
end
