defmodule CharonOauth2.Internal.AuthorizationValidator do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  import CharonOauth2.Internal
  alias CharonOauth2.Types.SeparatedStringOrdset

  @primary_key false
  embedded_schema do
    field :response_type, :string
    field :client_id, Ecto.UUID
    field :redirect_uri, :string
    field :resolved_redir_uri, :string
    field :scope, SeparatedStringOrdset, pattern: [" ", ","]
    field :state, :string
    field :code_challenge, :string
    field :code_challenge_method, :string
    field :permission_granted, :boolean
    field :client, :any, virtual: true
  end

  @valid_response_types ~w(code token)
  @supported_response_types ~w(code)
  @valid_challenge_methods ~w(S256 plain)
  @supported_challenge_methods ~w(S256)
  @response_type_to_grant_type %{"code" => "authorization_code"}

  @doc """
  Both `:client_id` and `:redirect_uri` must be valid in order to redirect errors back to the oauth2 client.
  That is why errors from this changeset should result in a 400,
  so that they can be shown to the user.
  """
  def no_redirect_checks(params, client_context) do
    %__MODULE__{}
    |> cast(params, [:client_id, :redirect_uri])
    |> validate_required([:client_id])
    |> case do
      cs = %{valid?: true, changes: %{client_id: cid}} ->
        if client = client_context.get_by(id: cid) do
          cs |> put_change(:client, client) |> validate_client_redirect_uri(client)
        else
          add_error(cs, :client_id, "client not found")
        end

      cs ->
        cs
    end
    |> then(&{:no_redirect, &1})
  end

  @doc """
  Parameters must be "valid", that is, present, of the right type, with sane values etc.
  Otherwise we redirect "invalid_request" to the oauth2 client.
  """
  def missing_invalid_or_malformed(cs, params) do
    cs
    |> cast(params, [
      :response_type,
      :scope,
      :state,
      :code_challenge,
      :code_challenge_method
    ])
    |> validate_required([:response_type])
    |> validate_inclusion(:code_challenge_method, @valid_challenge_methods,
      message: "not recognized"
    )
    |> validate_inclusion(:response_type, @valid_response_types, message: "not recognized")
    |> then(&{:invalid, &1})
  end

  @doc """
  If the request is "valid" as per `missing_invalid_or_malformed/2`,
  other stuff can be wrong with the request depending on the client, the application scopes etc.
  Here we do those checks.
  """
  def other_checks(cs, params, client, scopes) do
    cs
    |> cast(params, [:permission_granted])
    |> validate_required([:permission_granted])
    |> validate_sub_ordset(:scope, scopes, "known scopes are #{Enum.join(scopes, ", ")}")
    |> validate_client_scopes(client)
    |> validate_inclusion(:response_type, @supported_response_types, message: "is unsupported")
    |> validate_client_response_type(client)
    |> then(fn
      cs = %{valid?: true, changes: %{response_type: resp_type}} ->
        type_dependent_validations(cs, resp_type)

      cs ->
        cs
    end)
    |> validate_inclusion(:permission_granted, [true], message: "no")
  end

  ###########
  # Private #
  ###########

  defp type_dependent_validations(cs, "code") do
    cs
    # PKCE (optional but required for public clients in original oauth2 spec)
    # mandatory in updated "oauth2.1" spec https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-07#name-differences-from-oauth-20
    |> validate_required(:code_challenge, message: "can't be blank (PKCE is required)")
    |> validate_required(:code_challenge_method)
    |> validate_inclusion(:code_challenge_method, @supported_challenge_methods,
      message: "is unsupported"
    )
  end

  # param redirect_uri is only required when multiple uris are configured for the client
  defp validate_client_redirect_uri(cs, _client = %{redirect_uris: uris}) do
    case uris do
      [_] -> cs
      _ -> validate_required(cs, :redirect_uri)
    end
    |> validate_ordset_element(:redirect_uri, uris)
    |> case do
      cs = %{valid?: true} ->
        resolved_uri = cs.changes[:redirect_uri] || List.first(uris)
        put_change(cs, :resolved_redir_uri, resolved_uri)

      cs ->
        cs
    end
  end

  # response type must be enabled for client
  defp validate_client_response_type(cs = %{valid?: true}, %{grant_types: grant_types}) do
    cs
    |> validate_change(:response_type, fn _, value ->
      grant_type = Map.get(@response_type_to_grant_type, value)

      if :ordsets.is_element(grant_type, grant_types) do
        []
      else
        [response_type: "not supported by client"]
      end
    end)
  end

  defp validate_client_response_type(cs, _), do: cs

  # scopes must be enabled for client
  defp validate_client_scopes(cs = %{valid?: true}, %{scope: scopes}) do
    validate_sub_ordset(cs, :scope, scopes, "client supports #{Enum.join(scopes, ", ")}")
  end

  defp validate_client_scopes(cs, _), do: cs
end
