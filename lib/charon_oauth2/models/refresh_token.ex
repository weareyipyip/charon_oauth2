defmodule CharonOauth2.Models.RefreshToken do
  @moduledoc """
  An oauth2 refresh token.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, except: [preload: 2, preload: 3]
  alias Ecto.Query
  alias CharonOauth2.Models.{Authorization}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "charon_oauth2_refresh_tokens" do
    field(:expires_at, :utc_datetime)

    belongs_to(:authorization, Authorization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Insert-only changeset - some things (should) never change.
  """
  @spec insert_only_changeset(__MODULE__.t() | Changeset.t(), map(), Charon.Config.t()) ::
          Changeset.t()
  def insert_only_changeset(struct_or_cs \\ %__MODULE__{}, params, config) do
    ttl = config.refresh_token_ttl

    struct_or_cs
    |> cast(params, [:authorization_id, :id])
    |> validate_required([:authorization_id])
    |> assoc_constraint(:authorization)
    |> unique_constraint(:id, name: "charon_oauth2_refresh_tokens_pkey")
    |> put_change(:expires_at, DateTime.from_unix!(ttl + Charon.Internal.now()))
  end

  ###########
  # Queries #
  ###########

  @doc """
  Sets the current module name as a camelcase named binding in an Ecto query
  """
  @spec named_binding() :: Query.t()
  def named_binding() do
    from(u in __MODULE__, as: :charon_oauth2_refresh_token)
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
        :authorization ->
          join(query, :left, [charon_oauth2_refresh_token: rt], a in assoc(rt, :authorization),
            as: :authorization
          )

        :authorization_client ->
          query
          |> resolve_binding(:authorization)
          |> join(:left, [authorization: a], c in assoc(a, :client), as: :client)
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
      :authorization ->
        query
        |> resolve_binding(:authorization)
        |> Query.preload([authorization: a], authorization: a)

      :authorization_client ->
        query
        |> resolve_binding(:authorization_client)
        |> Query.preload([authorization: a, client: c], authorization: {a, client: c})
    end
  end

  def preload(query, list), do: Enum.reduce(list, query, &preload(&2, &1))

  @doc false
  def supported_preloads(), do: ~w(authorization authorization_client)a
end
