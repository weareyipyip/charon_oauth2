defmodule CharonOauth2.Config do
  @moduledoc """
  Config module for `CharonOauth2`.

      Charon.Config.from_enum(
        ...,
        optional_modules: %{
          CharonOauth2 => %{
            scopes: []
          }
        }
      )
  """
  @enforce_keys [:scopes, :repo, :resource_owner_schema]
  defstruct [
    :repo,
    :resource_owner_schema,
    :scopes,
    grant_ttl: 10 * 60,
    grant_table: "charon_oauth2_grants",
    client_table: "charon_oauth2_clients",
    authorization_table: "charon_oauth2_authorizations",
    resource_owner_id_column: :id,
    resource_owner_id_type: :bigserial,
    customize_session_upsert_args: &Function.identity/1,
    verify_refresh_token: &CharonOauth2.verify_refresh_token/2
  ]

  @type t :: %__MODULE__{scopes: [String.t()], grant_ttl: pos_integer()}

  @doc """
  Build config struct from enumerable (useful for passing in application environment).
  Raises for missing mandatory keys and sets defaults for optional keys.
  """
  @spec from_enum(Enum.t()) :: t()
  def from_enum(enum), do: struct!(__MODULE__, enum)
end
