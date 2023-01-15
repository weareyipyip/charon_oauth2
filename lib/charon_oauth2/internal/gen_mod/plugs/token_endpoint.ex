defmodule CharonOauth2.Internal.GenMod.Plugs.TokenEndpoint do
  @moduledoc false

  def generate(schemas_and_contexts, _repo) do
    quote generated: true,
          bind_quoted: [
            grant_context: schemas_and_contexts.grants,
            auth_context: schemas_and_contexts.authorizations,
            client_context: schemas_and_contexts.clients
          ] do
      @moduledoc """
      The Oauth2 [token endpoint](https://www.rfc-editor.org/rfc/rfc6749#section-3.2).
      It must support request bodies with content type `application/x-www-form-urlencoded`,
      be sure to pipe the request through an appropriately set-up Plug.Parsers.

      ## Usage

          alias #{__MODULE__}

          # this endpoint must be public, without any additional authentication requirements
          forward "/oauth2/token", TokenEndpoint, config: @config
      """
      @behaviour Plug
      use Charon.Internal.Constants
      alias Plug.Conn
      alias Charon.{SessionPlugs, Utils}
      alias CharonOauth2.Internal
      alias Internal.TokenValidator, as: Validate
      import Conn
      import Charon.{Internal, TokenPlugs}
      import Internal.Plug

      @grant_context grant_context
      @auth_context auth_context
      @client_context client_context

      @impl true
      def init(opts) do
        config = Keyword.fetch!(opts, :config)
        config = %{config | session_ttl: :infinite}
        mod_conf = CharonOauth2.Internal.get_module_config(config)
        %{config: config, mod_conf: mod_conf}
      end

      @impl true
      def call(conn = %{method: "POST", path_info: [], body_params: params}, opts) do
        params = Map.put(params, "auth_header", get_req_header(conn, "authorization"))

        with cs = %{valid?: true} <-
               params
               |> Validate.cast_non_grant_type_params()
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

      def call(conn, _) do
        conn |> dont_cache() |> send_resp(404, "Not found")
      end

      ###########
      # Private #
      ###########

      defp process_grant(cs = %{changes: %{grant_type: "authorization_code"}}, conn, opts) do
        with cs = %{valid?: true, changes: %{code: code}} <-
               Validate.authorization_code_flow_step_1(cs),
             grant = %{authorization: authorization} <-
               @grant_context.get_by([code: code], [:authorization]),
             now = now(),
             grant_exp = DateTime.to_unix(grant.expires_at, :second),
             {_, false} <- {:expired?, grant_exp < now},
             %{valid?: true} <- Validate.authorization_code_flow_step_2(cs, grant) do
          # prevent authorization code reuse
          {:ok, _} = @grant_context.delete(id: grant.id)

          conn
          |> Utils.set_token_signature_transport(:bearer)
          |> Utils.set_user_id(grant.resource_owner_id)
          |> upsert_session(authorization, opts)
          |> send_token_response(authorization, now, opts)
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

              other ->
                json_error(conn, 400, "invalid_request", descr, opts)
            end
        end
      end

      defp process_grant(
             cs = %{changes: %{client: client, grant_type: grant_type = "refresh_token"}},
             conn,
             opts
           ) do
        with %{valid?: true, changes: %{refresh_token: token}} <- Validate.refresh_token_flow(cs),
             conn = Utils.set_token(conn, token),
             {:ok, conn, %{"sub" => uid, "cid" => cid}} <- verify_refresh_token(conn, opts),
             {_, true} <- {:client_id_matches?, cid == client.id},
             authorization = %{} <- @auth_context.get_by(resource_owner_id: uid, client_id: cid) do
          conn
          |> Utils.set_token_signature_transport(:bearer)
          |> upsert_session(authorization, opts)
          |> send_token_response(authorization, now(), opts)
        else
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

      defp upsert_session(conn, authorization, %{config: config, mod_conf: mod_conf}) do
        %{scope: scope, client_id: cid} = authorization

        [
          conn,
          config,
          [
            session_type: :oauth2,
            access_claim_overrides: %{"cid" => cid, "scope" => scope},
            refresh_claim_overrides: %{"cid" => cid, "scope" => scope}
          ]
        ]
        |> mod_conf.customize_session_upsert_args.()
        |> then(&apply(SessionPlugs, :upsert_session, &1))
      end

      defp send_token_response(conn, authorization, now, opts) do
        tokens = conn |> Utils.get_tokens()

        resp_body = %{
          access_token: tokens.access_token,
          expires_in: tokens.access_token_exp - now,
          refresh_expires_in: tokens.refresh_token_exp - now,
          refresh_token: tokens.refresh_token,
          scope: authorization.scope |> Enum.join(" "),
          token_type: "bearer"
        }

        json(conn, 200, resp_body, opts)
      end
    end
  end
end
