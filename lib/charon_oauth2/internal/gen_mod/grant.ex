defmodule CharonOauth2.Internal.GenMod.Grant do
  @moduledoc false

  def generate(%{authorization: authorization_schema}, config) do
    quote generated: true do
      @moduledoc """
      A grant is an (in-progress) Oauth2 flow to obtain auth tokens.

      Not every flow needs server-side state to be stored, for example, the implicit grant
      immediately returns an access token in response to the authorization request, and does
      not have a second exchange-code-for-token request-response cycle.
      """
      alias Ecto.{Query, Changeset, Schema}
      use Schema
      import Changeset
      import Query, except: [preload: 2, preload: 3]
      alias CharonOauth2.Types.{Hmac, Encrypted}
      alias CharonOauth2.Internal
      alias Charon.Internal, as: CharonInternal

      @type t :: %__MODULE__{}
      @typedoc "Bindings / preloads that can be used with `resolve_binding/2` and `preload/2`"
      @type resolvable ::
              :resource_owner
              | :authorization
              | :authorization_client
              | :authorization_resource_owner

      @config unquote(config)
      @mod_config Internal.get_module_config(@config)
      @auth_schema unquote(authorization_schema)
      @res_owner_schema @mod_config.resource_owner_schema

      @types ~w(authorization_code)
      @autogen_code {CharonInternal, :random_url_encoded, [32]}

      schema @mod_config.grants_table do
        field(:code, Hmac, autogenerate: @autogen_code, redact: true, config: @config)
        field(:redirect_uri, :string)
        field(:redirect_uri_specified, :boolean)
        field(:type, :string)
        field(:expires_at, :utc_datetime)
        field(:code_challenge, Encrypted, redact: true, config: @config)

        belongs_to(:authorization, @auth_schema)

        belongs_to(:resource_owner, @res_owner_schema,
          references: @mod_config.resource_owner_id_column,
          type: Internal.column_type_to_ecto_type(@mod_config.resource_owner_id_type)
        )

        timestamps(type: :utc_datetime)
      end

      @doc """
      Insert-only changeset - some things (should) never change.
      """
      @spec insert_only_changeset(__MODULE__.t() | Changeset.t(), map()) ::
              Changeset.t()
      def insert_only_changeset(struct_or_cs \\ %__MODULE__{}, params) do
        struct_or_cs
        |> cast(params, [
          :redirect_uri,
          :type,
          :authorization_id,
          :resource_owner_id,
          :code_challenge
        ])
        |> validate_required([
          :type,
          :authorization_id,
          :resource_owner_id
        ])
        |> validate_inclusion(:type, @types, message: "must be one of: #{Enum.join(@types, ", ")}")
        |> prepare_changes(fn cs = %{data: data} ->
          type = get_field(cs, :type)
          auth_id = get_field(cs, :authorization_id)
          res_owner_id = get_field(cs, :resource_owner_id)

          with authorization = %{client: client} <-
                 @auth_schema.preload(:client) |> cs.repo.get(auth_id),
               {_, true} <- {:type, :ordsets.is_element(type, client.grant_types)},
               {_, true} <- {:res_own, res_owner_id == authorization.resource_owner_id} do
            %{cs | data: %{data | authorization: authorization}}
            |> validate_redirect_uri(client)
            |> maybe_require_pkce(type, client)
          else
            {:type, _} -> add_error(cs, :type, "not supported by client")
            {:res_own, _} -> add_error(cs, :authorization_id, "belongs to other resource owner")
            nil -> cs
          end
        end)
        |> unique_constraint(:code)
        |> assoc_constraint(:authorization)
        |> assoc_constraint(:resource_owner)
        |> put_change(
          :expires_at,
          DateTime.from_unix!(@mod_config.grant_ttl + CharonInternal.now())
        )
      end

      ###########
      # Queries #
      ###########

      @doc """
      Sets the current module name as a camelcase named binding in an Ecto query
      """
      @spec named_binding() :: Query.t()
      def named_binding() do
        from(u in __MODULE__, as: :charon_oauth2_grant)
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
              join(query, :left, [charon_oauth2_grant: c], ro in assoc(c, :resource_owner),
                as: :resource_owner
              )

            :authorization ->
              join(query, :left, [charon_oauth2_grant: c], a in assoc(c, :authorization),
                as: :authorization
              )

            :authorization_client ->
              query
              |> resolve_binding(:authorization)
              |> join(:left, [authorization: a], c in assoc(a, :client), as: :authorization_client)

            :authorization_resource_owner ->
              query
              |> resolve_binding(:authorization)
              |> join(:left, [authorization: a], ro in assoc(a, :resource_owner),
                as: :authorization_resource_owner
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

          :authorization ->
            query
            |> resolve_binding(:authorization)
            |> Query.preload([authorization: a], authorization: a)

          :authorization_client ->
            query
            |> resolve_binding(:authorization_client)
            |> Query.preload([authorization: a, authorization_client: c],
              authorization: {a, client: c}
            )

          :authorization_resource_owner ->
            query
            |> resolve_binding(:authorization_resource_owner)
            |> Query.preload([authorization: a, authorization_resource_owner: ro],
              authorization: {a, resource_owner: ro}
            )
        end
      end

      def preload(query, list), do: Enum.reduce(list, query, &preload(&2, &1))

      @doc false
      # used for tests
      def supported_preloads() do
        [
          :resource_owner,
          :authorization,
          :authorization_client,
          :authorization_resource_owner
        ]
      end

      ###########
      # Private #
      ###########

      # require PKCE for authorization_code-type grants for public clients
      defp maybe_require_pkce(changeset, "authorization_code", client = %{client_type: "public"}) do
        validate_required(changeset, :code_challenge)
      end

      defp maybe_require_pkce(changeset, _grant_type, _client), do: changeset

      # param redirect_uri is only required when multiple uris are configured for the client
      defp validate_redirect_uri(cs, _client = %{redirect_uris: uris}) do
        case uris do
          [_] -> cs
          _ -> validate_required(cs, :redirect_uri)
        end
        |> Internal.validate_ordset_contains(:redirect_uri, uris, "does not match client")
        |> then(fn cs ->
          redirect_uri = cs.changes[:redirect_uri]

          cs
          |> put_change(:redirect_uri, redirect_uri || List.first(uris))
          |> put_change(:redirect_uri_specified, not is_nil(redirect_uri))
        end)
      end
    end
  end
end
