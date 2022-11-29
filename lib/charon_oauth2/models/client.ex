defmodule CharonOauth2.Models.Client do
  @moduledoc """
  An Oauth2 (third-party) client application.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, except: [preload: 2, preload: 3]
  alias Ecto.Query
  alias CharonOauth2.Types.SeparatedString
  alias CharonOauth2.Internal
  import Internal

  @type t :: %__MODULE__{}

  @client_types ~w(confidential public)
  @grant_types ~w(authorization_code refresh_token)
  @resource_owner_schema Application.compile_env!(:charon_oauth2, :resource_owner_schema)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "charon_oauth2_clients" do
    field(:name, :string)
    field(:secret, :string, redact: true, autogenerate: {Internal, :random_string, [256]})
    field(:redirect_uris, SeparatedString, pattern: ",")
    field(:scopes, SeparatedString, pattern: ",")
    field(:grant_types, SeparatedString, pattern: ",")
    field(:client_type, :string, default: "confidential")

    # has_many(:authorizations, Authorization, foreign_key: :client_id)
    belongs_to(:owner, @resource_owner_schema)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Basic changeset.
  """
  @spec changeset(__MODULE__.t() | Changeset.t(), map(), Charon.Config.t()) :: Changeset.t()
  def changeset(struct_or_cs \\ %__MODULE__{}, params, config) do
    config = get_module_config(config)

    struct_or_cs
    |> cast(params, [:name, :redirect_uris, :scopes, :grant_types, :client_type, :secret])
    |> validate_required([:name, :redirect_uris, :scopes, :grant_types, :client_type])
    |> multifield_apply([:redirect_uris, :scopes, :grant_types], fn cs, fld ->
      update_change(cs, fld, &Enum.uniq/1)
    end)
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
    |> update_change(:secret, fn _ -> random_string(256) end)
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

  @doc false
  @spec named_binding() :: Query.t()
  def named_binding() do
    from(u in __MODULE__, as: :charon_oauth2_client)
  end

  @doc false
  @spec preload(Query.t(), atom | [atom]) :: Query.t()
  def preload(query \\ named_binding(), named_binding_or_bindings)
  def preload(query, []), do: query
  def preload(query, [head | tail]), do: query |> preload(head) |> preload(tail)

  def preload(query, named_binding) do
    case named_binding do
      :authorizations ->
        Query.preload(query, :authorizations)

      :authorizations_grants ->
        Query.preload(query, authorizations: [:grants])

      _ ->
        query
    end
  end
end
