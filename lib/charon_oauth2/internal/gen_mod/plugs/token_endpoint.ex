defmodule CharonOauth2.Internal.GenMod.Plugs.TokenEndpoint do
  @moduledoc false

  def generate(schemas_and_contexts, _repo) do
    quote location: :keep,
          generated: true,
          bind_quoted: [schemas_and_contexts: schemas_and_contexts] do
      @moduledoc """
      The Oauth2 [token endpoint](https://www.rfc-editor.org/rfc/rfc6749#section-3.2).

      There is no need to pass the conn through `Plug.Parsers`, because it does so by itself.
      The endpoint only accepts content type `application/x-www-form-urlencoded` with utf-8 params.
      The exceptions raised by Plug.Parsers simply bubble up,
      your application must return appropriate responses for them (Phoenix applications should do so by default).

      ## Usage

          alias #{__MODULE__}

          # this endpoint must be public, without any additional authentication requirements
          forward "/oauth2/token", TokenEndpoint, config: @config

      ## Client authentication

      Confidential clients must authenticate using their client secret (and public clients may do so too
      although there would be little point in it if they can't keep their secret, you know, secret).

      HTTP Basic authentication takes precedence over req body credentials.
      Although [the spec](https://datatracker.ietf.org/doc/html/rfc6749#section-2.3)
      says clients must not use more than one auth method,
      it doesn't say auth servers should reject such requests,
      so we simply decided that HTTP Basic takes priority,
      because the same spec says that HTTP Basic, at least, *must* be supported
      for clients that identify using a client password.

      IF HTTP Basic auth is used, an authentication failure results in a 401 response with
      header "www-authenticate" set to "Basic", instead of a "normal" 400-with-JSON error response.

      ## Authorization code with Proof Key for Code Exchange (PKCE) enforced

      The Oauth 2.1 [draft spec](https://www.ietf.org/archive/id/draft-ietf-oauth-v2-1-07.html) recommends
      enforcing PKCE for the authorization_code grant under all circumstances. That is what we do.

      ## Sessions

      Tokens handed out by this endpoint are backed by a server-side session (that is only loaded on refresh, by default).
      The session type is `:oauth2`, separating these sessions from other sessions that the user may have in `Charon`.
      The purpose of this separation is to be able to call delete-all and not drop oauth2-client connections,
      or the other way around.
      """
      @behaviour Plug
      use Charon.Internal.Constants
      alias Plug.{Conn, Parsers}
      alias Charon.{SessionPlugs, Utils}
      alias CharonOauth2.Internal
      alias Internal.TokenValidator, as: Validate
      import Conn
      import Charon.{Internal, TokenPlugs}
      import Internal.Plug

      @grant_context schemas_and_contexts.grants
      @auth_context schemas_and_contexts.authorizations
      @client_context schemas_and_contexts.clients

      @parser_opts Parsers.init(
                     parsers: [:urlencoded],
                     pass: [],
                     validate_utf8: true,
                     length: 1_000_000
                   )

      @impl true
      def init(opts) do
        config = Keyword.fetch!(opts, :config)
        config = %{config | session_ttl: :infinite, enforce_browser_cookies: false}
        mod_conf = CharonOauth2.Internal.get_module_config(config)
        %{config: config, mod_conf: mod_conf}
      end

      @impl true
      def call(conn = %{method: "POST", path_info: []}, opts) do
        conn = conn |> Parsers.call(@parser_opts) |> add_cors_headers()

        params = conn.body_params |> Map.put("auth_header", get_req_header(conn, "authorization"))

        with cs = %{valid?: true} <-
               params
               |> Validate.cast_params()
               |> Validate.grant_type()
               |> Validate.authenticate_client(@client_context) do
          process_grant(cs, conn, opts)
        else
          invalid_cs ->
            error_map = changeset_errors_to_map(invalid_cs)
            descr = error_map |> cs_error_map_to_string()

            error_map
            |> case do
              %{grant_type: ["server supports " <> _]} ->
                json_error(conn, 400, "unsupported_grant_type", descr, opts)

              errors = %{auth_header: _} ->
                conn
                |> put_resp_header("www-authenticate", "Basic")
                |> dont_cache()
                |> send_resp(401, descr)

              %{client_secret: err} when err != ["is invalid"] ->
                json_error(conn, 400, "invalid_client", descr, opts)

              _other ->
                json_error(conn, 400, "invalid_request", descr, opts)
            end
        end
      end

      # CORS preflight request for browser clients that use the authorization header
      # to authenticate a confidential client (though they should use a public client)
      def call(conn = %{method: "OPTIONS", path_info: []}, %{mod_conf: mod_conf}) do
        conn |> add_cors_headers() |> send_resp(204, "")
      end

      def call(conn, _) do
        conn |> dont_cache() |> send_resp(404, "Not found")
      end

      ###########
      # Private #
      ###########

      defp process_grant(
             cs = %{changes: %{grant_type: "client_credentials", client: client}},
             conn,
             opts
           ) do
        dummy_auth = %{scope: client.scope, client: client, client_id: client.owner_id}

        with cs = %{valid?: true} <- Validate.client_credentials_flow(cs, dummy_auth) do
          scopes = Map.get(cs.changes, :scope, dummy_auth.scope)

          conn
          |> upsert_session(dummy_auth, scopes, opts, user_id: client.id)
          |> send_token_response(scopes, now(), opts, false)
        else
          invalid_cs ->
            error_map = changeset_errors_to_map(invalid_cs)
            descr = error_map |> cs_error_map_to_string()

            error_map
            |> case do
              %{scope: ["user authorized " <> _]} ->
                json_error(conn, 400, "invalid_scope", descr, opts)

              %{grant_type: ["unsupported by client"]} ->
                json_error(conn, 400, "unauthorized_client", descr, opts)

              other ->
                json_error(conn, 400, "invalid_request", descr, opts)
            end
        end
      end

      defp process_grant(cs = %{changes: %{grant_type: "authorization_code"}}, conn, opts) do
        with cs = %{valid?: true, changes: %{code: code}} <-
               Validate.authorization_code_flow_step_1(cs),
             grant = %{authorization: authorization} <-
               @grant_context.get_by([code: code], [:authorization]),
             now = now(),
             grant_exp = DateTime.to_unix(grant.expires_at, :second),
             {_, false} <- {:expired?, grant_exp < now},
             cs = %{valid?: true} <- Validate.authorization_code_flow_step_2(cs, grant) do
          # prevent authorization code reuse
          {:ok, _} = @grant_context.delete(id: grant.id)
          scopes = Map.get(cs.changes, :scope, authorization.scope)

          conn
          |> upsert_session(authorization, scopes, opts, user_id: grant.resource_owner_id)
          |> send_token_response(scopes, now, opts, true)
        else
          # https://datatracker.ietf.org/doc/html/rfc6749#section-5.2
          # grant not found
          nil ->
            json_error(conn, 400, "invalid_grant", "code: not found", opts)

          {:expired?, true} ->
            json_error(conn, 400, "invalid_grant", "code: expired", opts)

          invalid_cs ->
            error_map = changeset_errors_to_map(invalid_cs)
            descr = error_map |> cs_error_map_to_string()

            error_map
            |> case do
              %{client_id: ["does not match code"]} ->
                json_error(conn, 400, "invalid_grant", descr, opts)

              %{grant_type: ["unsupported by client"]} ->
                json_error(conn, 400, "unauthorized_client", descr, opts)

              %{redirect_uri: ["does not match grant"]} ->
                json_error(conn, 400, "invalid_grant", descr, opts)

              %{scope: ["user authorized " <> _]} ->
                json_error(conn, 400, "invalid_scope", descr, opts)

              other ->
                json_error(conn, 400, "invalid_request", descr, opts)
            end
        end
      end

      # https://datatracker.ietf.org/doc/html/rfc6749#section-6
      defp process_grant(
             cs = %{changes: %{client: client, grant_type: grant_type = "refresh_token"}},
             conn,
             opts
           ) do
        with cs = %{valid?: true, changes: %{refresh_token: token}} <-
               Validate.refresh_token_flow_step_1(cs),
             conn = Utils.set_token(conn, token),
             {:ok, conn, %{"sub" => uid, "cid" => cid}} <- verify_refresh_token(conn, opts),
             # the token must belong to the authenticated client
             {_, true} <- {:client_id_matches?, cid == client.id},
             # the user must still have authorized the client
             authorization = %{} <- @auth_context.get_by(resource_owner_id: uid, client_id: cid),
             cs = %{valid?: true} <- Validate.refresh_token_flow_step_2(cs, authorization) do
          scopes = Map.get(cs.changes, :scope, authorization.scope)

          conn
          |> upsert_session(authorization, scopes, opts)
          |> send_token_response(scopes, now(), opts, true)
        else
          conn = %Plug.Conn{} ->
            conn

          {:refresh_token_error, err} ->
            json_error(conn, 400, "invalid_grant", "refresh_token: #{err}", opts)

          nil ->
            json_error(conn, 400, "invalid_grant", "authorization: not found", opts)

          {:client_id_matches?, _} ->
            descr = "client_id: does not match refresh token"
            json_error(conn, 400, "invalid_grant", descr, opts)

          invalid_cs ->
            error_map = changeset_errors_to_map(invalid_cs)
            descr = error_map |> cs_error_map_to_string()

            error_map
            |> case do
              %{grant_type: ["unsupported by client"]} ->
                json_error(conn, 400, "unauthorized_client", descr, opts)

              %{scope: ["user authorized " <> _]} ->
                json_error(conn, 400, "invalid_scope", descr, opts)

              other ->
                json_error(conn, 400, "invalid_request", descr, opts)
            end
        end
      end

      defp verify_refresh_token(conn, _opts = %{config: config, mod_conf: mod_conf}) do
        conn = mod_conf.verify_refresh_token.(conn, config)

        cond do
          error = Utils.get_auth_error(conn) -> {:refresh_token_error, error}
          payload = Utils.get_bearer_token_payload(conn) -> {:ok, conn, payload}
        end
      end

      defp upsert_session(conn, authorization, scopes, opts, upsert_opts \\ []) do
        %{client_id: cid} = authorization

        base_upsert_opts = [
          token_transport: :bearer,
          session_type: :oauth2,
          access_claim_overrides: %{"cid" => cid, "scope" => scopes},
          refresh_claim_overrides: %{"cid" => cid}
        ]

        [conn, opts.config, base_upsert_opts ++ upsert_opts]
        |> opts.mod_conf.customize_session_upsert_args.()
        |> then(&apply(SessionPlugs, :upsert_session, &1))
      end

      defp send_token_response(conn, scopes, now, opts, incl_refresh_token) do
        resp_body = conn |> Utils.get_tokens() |> resp_body(scopes, now, incl_refresh_token)
        json(conn, 200, resp_body, opts)
      end

      defp resp_body(tokens, scopes, now, _incl_refresh_token = true) do
        %{
          access_token: tokens.access_token,
          expires_in: tokens.access_token_exp - now,
          refresh_expires_in: tokens.refresh_token_exp - now,
          refresh_token: tokens.refresh_token,
          scope: scopes |> Enum.join(" "),
          token_type: "bearer"
        }
      end

      defp resp_body(tokens, scopes, now, _) do
        %{
          access_token: tokens.access_token,
          expires_in: tokens.access_token_exp - now,
          scope: scopes |> Enum.join(" "),
          token_type: "bearer"
        }
      end

      defp add_cors_headers(conn) do
        merge_resp_headers(conn, %{
          "access-control-allow-methods" => "POST",
          # content-type does need need to be whitelisted, technically, because
          # application/x-www-form-urlencoded counts as a "simple" request
          "access-control-allow-headers" => "authorization,content-type",
          "access-control-allow-origin" => "*"
        })
      end
    end
  end
end
