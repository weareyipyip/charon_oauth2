defmodule CharonOauth2.Internal.TokenValidator do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  use Charon.Internal.Constants
  import Charon.Internal
  import CharonOauth2.Internal
  import Plug.Crypto, only: [secure_compare: 2]

  @primary_key false
  embedded_schema do
    field :grant_type, :string
    field :code, :string
    field :redirect_uri, :string
    field :client_id, Ecto.UUID
    field :client_secret, :string
    field :refresh_token, :string
    field :code_verifier, :string
    field :client, :any, virtual: true
    field :auth_header, :any, virtual: true
  end

  @grant_types ~w(authorization_code refresh_token)

  def cast_non_grant_type_params(params) do
    %__MODULE__{}
    |> cast(params, [
      :grant_type,
      :code,
      :redirect_uri,
      :client_id,
      :client_secret,
      :refresh_token,
      :code_verifier,
      :auth_header
    ])
    |> validate_auth_header()
  end

  def grant_type(cs = %{valid?: true}) do
    cs
    |> validate_required([:grant_type])
    |> validate_inclusion(:grant_type, @grant_types,
      message: "server supports [#{Enum.join(@grant_types, ", ")}]"
    )
  end

  def grant_type(cs), do: cs

  def authenticate_client(cs = %{valid?: true}, client_context) do
    cs
    |> validate_required(:client_id)
    |> load_client(client_context)
    |> validate_client_secret()
    |> maybe_add_auth_header_error()
  end

  def authenticate_client(cs, _), do: cs

  # https://datatracker.ietf.org/doc/html/rfc6749#section-4.1.3
  def authorization_code_flow_step_1(cs) do
    cs |> validate_required([:code])
  end

  def authorization_code_flow_step_2(cs, grant = %{authorization: authorization}) do
    cs
    |> validate_inclusion(:client_id, [authorization.client_id], message: "does not match code")
    |> validate_client_grant_type(cs.changes.client)
    |> validate_redirect_uri(grant)
    |> validate_pkce(grant)
  end

  # https://datatracker.ietf.org/doc/html/rfc6749#section-6
  def refresh_token_flow(cs) do
    client = cs.changes.client
    cs |> validate_required([:refresh_token]) |> validate_client_grant_type(client)
  end

  ###########
  # Private #
  ###########

  defp validate_auth_header(cs = %{changes: %{auth_header: auth_header}}) do
    with {_, [value]} <- {:header, auth_header},
         "Basic " <> encoded_user_and_pass <- value,
         {:ok, decoded_user_and_pass} <- Base.decode64(encoded_user_and_pass),
         [cid, secret] <- String.split(decoded_user_and_pass, ":", parts: 2, trim: true) do
      cast(cs, %{client_id: cid, client_secret: secret}, [:client_id, :client_secret])
      |> maybe_add_auth_header_error()
    else
      {:header, []} -> delete_change(cs, :auth_header)
      {:header, _} -> add_error(cs, :auth_header, "set multiple times")
      _ -> add_error(cs, :auth_header, "invalid HTTP basic authentication")
    end
  end

  defp load_client(cs = %{valid?: true}, client_context) do
    if client = client_context.get_by(id: cs.changes.client_id) do
      put_change(cs, :client, client)
    else
      add_error(cs, :client_id, "client not found")
    end
  end

  defp load_client(cs, _), do: cs

  defp validate_client_secret(cs = %{valid?: true, changes: %{client: client}}) do
    if(client.client_type == "confidential", do: validate_required(cs, :client_secret), else: cs)
    |> validate_change(:client_secret, fn _, value ->
      if secure_compare(value, client.secret) do
        []
      else
        [client_secret: "does not match expected value"]
      end
    end)
  end

  defp validate_client_secret(cs), do: cs

  # add an error to field :basic auth if the cs is invalid and :auth_header is set
  defp maybe_add_auth_header_error(cs = %{valid?: false, changes: %{auth_header: _}}),
    do: add_error(cs, :auth_header, "is invalid")

  defp maybe_add_auth_header_error(cs), do: cs

  defp validate_redirect_uri(cs, _grant = %{redirect_uri: uri, redirect_uri_is_default: false}) do
    cs
    |> validate_required([:redirect_uri])
    |> validate_inclusion(:redirect_uri, [uri], message: "does not match grant")
  end

  defp validate_redirect_uri(cs, _grant = %{redirect_uri: uri}) do
    cs
    |> validate_inclusion(:redirect_uri, [uri], message: "does not match grant")
    |> case do
      cs = %{changes: %{redirect_uri: _}} -> cs
      cs -> put_change(cs, :redirect_uri, uri)
    end
  end

  # https://www.rfc-editor.org/rfc/rfc7636#section-4.6
  defp validate_pkce(cs, _grant = %{code_challenge: nil}), do: cs

  defp validate_pkce(cs, _grant = %{code_challenge: challenge}) do
    cs
    |> validate_required(:code_verifier)
    |> validate_change(:code_verifier, fn _, verifier ->
      exp_challenge = :crypto.hash(:sha256, verifier) |> url_encode()

      if secure_compare(exp_challenge, challenge) do
        []
      else
        [code_verifier: "does not match expected value"]
      end
    end)
  end

  defp validate_client_grant_type(cs, _client = %{grant_types: grant_types}) do
    validate_ordset_element(cs, :grant_type, grant_types, "unsupported by client")
  end
end
