defmodule CharonOauth2.Internal.GenMod.Plugs.AuthorizationEndpoint do
  @moduledoc false

  def generate(schemas_and_contexts, repo) do
    quote generated: true,
          bind_quoted: [
            grant_context: schemas_and_contexts.grants,
            auth_context: schemas_and_contexts.authorizations,
            client_context: schemas_and_contexts.clients,
            repo: repo
          ] do
      @moduledoc """
      The Oauth2 [authorization endpoint](https://www.rfc-editor.org/rfc/rfc6749#section-3.1).

      This endpoint is meant to be combined with a first-party web client in which a user can grant or deny access.
      So it does not, by itself, behave as an oauth2 authorization endpoint (for example, it only supports POST requests).
      The endpoint returns a JSON response with 200 OK and a `redirect_to` parameter,
      that the web client should then, you know, redirect to.
      The redirect may also contain an error result.
      However, there are some errors that must not result in redirection,
      for example errors in validating the redirect URI itself.
      Such errors result in a 400 response with an error description,
      that the companion web client may show to the user at its discretion.

      User must be logged-in using Charon (at least `Charon.TokenPlugs.verify_token_signature/2` must be called on the conn.)

      ## Usage

          alias #{__MODULE__}

          # this endpoint MUST only be useable by the first-party authorizing client!!!
          forward "/oauth2/authorize", AuthorizationEndpoint, config: @config
      """
      @behaviour Plug
      use Charon.Internal.Constants
      alias CharonOauth2.Internal.AuthorizationValidator, as: Validate
      alias CharonOauth2.Internal
      alias Plug.Conn
      alias Charon.Utils
      import Conn
      import Internal.Plug

      @grant_context grant_context
      @auth_context auth_context
      @client_context client_context
      @repo repo

      @impl true
      def init(opts) do
        config = Keyword.fetch!(opts, :config)
        mod_conf = CharonOauth2.Internal.get_module_config(config)
        scopes = mod_conf.scopes |> MapSet.new()
        %{config: config, mod_conf: mod_conf, scopes: scopes}
      end

      @impl true
      def call(
            conn = %{method: "POST", path_info: [], body_params: params},
            opts = %{config: config, scopes: scopes}
          ) do
        with {_, cs = %{valid?: true, changes: %{client: client}}} <-
               Validate.no_redirect_checks(params, @client_context),
             {_, cs = %{valid?: true}} <-
               Validate.missing_invalid_or_malformed(cs, params),
             cs = %{valid?: true, changes: %{response_type: response_type}} <-
               Validate.other_checks(cs, params, client, scopes) do
          do_authorize(response_type, conn, cs)
        else
          # on errors with the redirect_uri or the client_id, we don't redirect, as per the spec
          # we reply to the web client so that it may show an error to the user
          {:no_redirect, cs} ->
            json(conn, 400, %{errors: changeset_errors_to_map(cs)}, opts)

          {:invalid, cs} ->
            descr = cs |> changeset_errors_to_map() |> cs_error_map_to_string()
            error_redirect(conn, cs, "invalid_request", descr)

          cs ->
            error_map = changeset_errors_to_map(cs)
            descr = error_map |> cs_error_map_to_string()

            error_map
            |> case do
              %{response_type: ["is unsupported"]} ->
                error_redirect(conn, cs, "unsupported_response_type", descr)

              %{response_type: ["not supported by client"]} ->
                error_redirect(conn, cs, "unauthorized_client", descr)

              %{permission_granted: ["no"]} ->
                error_redirect(conn, cs, "access_denied", descr)

              %{permission_granted: errors} ->
                resp = %{errors: %{permission_granted: errors}}
                json(conn, 400, resp, opts)

              %{scope: ["known scopes are " <> scopes]} ->
                error_redirect(conn, cs, "invalid_scope", descr)

              %{scope: ["client supports " <> scopes]} ->
                error_redirect(conn, cs, "access_denied", descr)

              _other ->
                error_redirect(conn, cs, "invalid_request", descr)
            end
        end
      end

      def call(conn, _) do
        conn |> dont_cache() |> send_resp(404, "Not found")
      end

      ###########
      # Private #
      ###########

      defp do_authorize("code", conn, req_params_cs = %{changes: req_params}) do
        with %{"sub" => uid} = Utils.get_bearer_token_payload(conn),
             {:ok, authorization} <- upsert_authorization(uid, req_params),
             grant_params =
               %{
                 authorization_id: authorization.id,
                 resource_owner_id: uid,
                 type: "authorization_code",
                 redirect_uri: req_params[:redirect_uri]
               }
               |> put_non_nil(:code_challenge, req_params[:code_challenge]),
             {:ok, grant} <- @grant_context.insert(grant_params) do
          query_params = %{code: grant.code} |> put_non_nil(:state, req_params[:state])
          redirect_with_query(conn, req_params.resolved_redir_uri, query_params)
        else
          cs ->
            descr = cs |> changeset_errors_to_map() |> cs_error_map_to_string()
            error_redirect(conn, req_params_cs, "invalid_request", descr)
        end
      end

      defp upsert_authorization(user_id, req_params = %{client_id: client_id}) do
        ids = %{client_id: client_id, resource_owner_id: user_id}
        # scope is not updated if the parameter is not present
        params = req_params |> Map.take([:scope]) |> Map.merge(ids)
        getter = fn -> @auth_context.get_by(ids) end
        update = fn auth -> @auth_context.update(auth, params) end
        insert = fn -> @auth_context.insert(params) end
        Internal.upsert(getter, update, insert, @repo)
      end
    end
  end
end
