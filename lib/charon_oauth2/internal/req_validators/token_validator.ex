defmodule CharonOauth2.Internal.TokenValidator do
  @moduledoc false
  use Ecto.Schema
  alias Ecto.Changeset
  import Changeset
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

  @doc """
  All parameters must pass type validation or return an "invalid_request" response.
  """
  @spec cast_params(map()) :: Changeset.t()
  def cast_params(params) do
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

  @doc """
  Grant type must be specified and results in a separate "unsupported_grant_type" error
  if the server doesn't support it.
  """
  @spec grant_type(Changeset.t()) :: Changeset.t()
  def grant_type(cs = %{valid?: true}) do
    cs
    |> validate_required([:grant_type])
    |> validate_inclusion(:grant_type, @grant_types,
      message: "server supports [#{Enum.join(@grant_types, ", ")}]"
    )
  end

  def grant_type(cs), do: cs

  @doc """
  We authenticate the client.
  HTTP Basic authentication takes precedence over req body credentials.
  Although [the spec](https://datatracker.ietf.org/doc/html/rfc6749#section-2.3)
  says clients must not use more than one auth method,
  it doesn't say auth servers should reject such requests,
  so we simply decided that HTTP Basic takes priority,
  because the same spec says that HTTP Basic, at least, *must* be supported
  for clients that identify using a client password.

  Anyway, client_id must be set, must be a valid UUID, the client must exist,
  and the client_secret must be correct for confidential clients,
  and must be correct for public clients if it is passed as a parameter.

  Complicating things is the requirement in [another part of the spec](https://datatracker.ietf.org/doc/html/rfc6749#section-5.2)
  that a request authenticating using HTTP Basic must return a 401 response
  with a "www-authenticate" header, as opposed to the regular 400 response with
  an "invalid_client" error. That is why, if the cs is invalid and :auth_header is set,
  an error is added to :auth_header so that the endpoint code can return a different response.
  """
  @spec authenticate_client(Changeset.t(), module()) :: Changeset.t()
  def authenticate_client(cs = %{valid?: true}, client_context) do
    cs
    |> validate_required(:client_id)
    |> load_client(client_context)
    |> validate_client_secret()
    |> maybe_add_auth_header_error()
  end

  def authenticate_client(cs, _), do: cs

  @doc """
  We validate that the `code` param is set.
  https://datatracker.ietf.org/doc/html/rfc6749#section-4.1.3
  """
  @spec authorization_code_flow_step_1(Changeset.t()) :: Changeset.t()
  def authorization_code_flow_step_1(cs) do
    cs |> validate_required([:code])
  end

  @doc """
  After grabbing the grant and its parent authorization from the DB using the code param,
  we verify that:
   - authorization's client_id matches the authenticated client from `authenticate_client/1`
   - the grant type is enabled for the client
   - the redirect_uri is specified if it was specified during authorization
   - the redirect_uri matches the grant redirect_uri
   - PKCE checks out (code_verifier is present and matches grant's code_challenge)
  """
  @spec authorization_code_flow_step_2(Changeset.t(), struct()) :: Changeset.t()
  def authorization_code_flow_step_2(cs, grant = %{authorization: authorization}) do
    cs
    |> validate_inclusion(:client_id, [authorization.client_id], message: "does not match code")
    |> validate_client_grant_type(cs.changes.client)
    |> validate_redirect_uri(grant)
    |> validate_pkce(grant)
  end

  @doc """
  For the refresh token flow, we verify that a token is present and that the client
  supports the grant type.

  https://datatracker.ietf.org/doc/html/rfc6749#section-6
  """
  @spec refresh_token_flow(Changeset.t()) :: Changeset.t()
  def refresh_token_flow(cs) do
    client = cs.changes.client
    cs |> validate_required([:refresh_token]) |> validate_client_grant_type(client)
  end

  ###########
  # Private #
  ###########

  # validate the authorization header if it was set
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

  # grab the client from the DB if client_id was set
  defp load_client(cs = %{valid?: true}, client_context) do
    if client = client_context.get_by(id: cs.changes.client_id) do
      put_change(cs, :client, client)
    else
      add_error(cs, :client_id, "client not found")
    end
  end

  defp load_client(cs, _), do: cs

  # the client_secret must be correct for confidential clients
  # and must be correct for public clients if it is passed as a parameter
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

  # add an error to field :auth_header if the cs is invalid and :auth_header is set
  # https://datatracker.ietf.org/doc/html/rfc6749#section-5.2
  defp maybe_add_auth_header_error(cs = %{valid?: false, changes: %{auth_header: _}}),
    do: add_error(cs, :auth_header, "is invalid")

  defp maybe_add_auth_header_error(cs), do: cs

  # the redirect_uri is required IF it was specified in the authorization request
  # https://datatracker.ietf.org/doc/html/rfc6749#section-4.1.3
  # this is stored in the grant as redirect_uri_specified: true
  defp validate_redirect_uri(cs, _grant = %{redirect_uri: uri, redirect_uri_specified: true}) do
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

  # PKCE was added as an optional extra to the oauth2 auth code grant by RFC7636
  # but in "Oauth 2.1" it is recommended to be enforced in all circumstances
  # and that is what we do
  # https://www.rfc-editor.org/rfc/rfc7636#section-4.6
  # https://www.ietf.org/archive/id/draft-ietf-oauth-v2-1-07.html#name-authorization-codes

  defp validate_pkce(cs = %{changes: %{code_verifier: _}}, _grant = %{code_challenge: nil}) do
    # https://www.ietf.org/archive/id/draft-ietf-oauth-v2-1-07.html#section-7.6
    # this is technically kinda pointless because we enforce that the challenge is present
    add_error(cs, :code_verifier, "no challenge issued in authorization request")
  end

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

  # the grant type must be enabled for the client,
  # in addition to being supported by the server in the first place
  defp validate_client_grant_type(cs, _client = %{grant_types: grant_types}) do
    validate_ordset_contains(cs, :grant_type, grant_types, "unsupported by client")
  end
end
