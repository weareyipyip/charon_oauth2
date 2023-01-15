defmodule CharonOauth2.Plugs.TokenEndpointTest do
  use CharonOauth2.DataCase
  alias Charon.Models.Session
  alias MyApp.CharonOauth2.{Plugs.TokenEndpoint, Grants, Clients}
  import MyApp.{Seeds, TestUtils}
  import Plug.Test
  import Plug.Conn
  import Charon.{Internal, Utils, TestHelpers}

  @config MyApp.CharonOauth2.Config.get()

  setup do
    client = insert_test_client(grant_types: ~w(authorization_code refresh_token))
    user = insert_test_user()
    authorization = insert_test_authorization(client_id: client.id, resource_owner_id: user.id)
    grant = insert_test_grant(authorization_id: authorization.id, resource_owner_id: user.id)
    opts = TokenEndpoint.init(config: @config)
    [client: client, opts: opts, user: user, authorization: authorization, grant: grant]
  end

  describe "call/2" do
    test "returns 404 for other method/path", seeds do
      assert %{status: 404} =
               conn(:get, "/") |> TokenEndpoint.call(seeds.opts) |> assert_dont_cache()

      assert %{status: 404} =
               conn(:post, "/test") |> TokenEndpoint.call(seeds.opts) |> assert_dont_cache()
    end

    test "all parameters must be castable", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" =>
                 "client_id: is invalid, client_secret: is invalid, code: is invalid, code_verifier: is invalid, grant_type: is invalid, redirect_uri: is invalid, refresh_token: is invalid"
             } ==
               conn(:post, "/", %{
                 grant_type: {:boom},
                 code: {:boom},
                 redirect_uri: {:boom},
                 client_id: "not a uuid",
                 client_secret: {:boom},
                 refresh_token: {:boom},
                 code_verifier: {:boom}
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "grant_type is required and must be supported", seeds do
      assert %{"error" => "invalid_request", "error_description" => "grant_type: can't be blank"} ==
               conn(:post, "/", %{})
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "unspported grant type returns error 'unsupported_grant_type'", seeds do
      assert %{
               "error" => "unsupported_grant_type",
               "error_description" =>
                 "grant_type: server supports [authorization_code, refresh_token]"
             } ==
               conn(:post, "/", %{grant_type: "test"})
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "client_secret is not required for public clients", seeds do
      assert {:ok, _} = Clients.update(seeds.client, %{client_type: "public"})

      conn(:post, "/", %{
        grant_type: "authorization_code",
        code: seeds.grant.code,
        client_id: seeds.client.id,
        redirect_uri: seeds.grant.redirect_uri
      })
      |> TokenEndpoint.call(seeds.opts)
      |> assert_dont_cache()
      |> json_response(200)
    end

    test "client_secret is checked if it is set, even for public clients", seeds do
      assert {:ok, _} = Clients.update(seeds.client, %{client_type: "public"})
      basic_auth = Plug.BasicAuth.encode_basic_auth(seeds.client.id, "whatevs")

      assert "auth_header: is invalid, client_secret: does not match expected value" ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 redirect_uri: seeds.grant.redirect_uri
               })
               |> put_req_header("authorization", basic_auth)
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> assert_status(401)
               |> assert_resp_headers(%{"www-authenticate" => "Basic"})
               |> Map.get(:resp_body)

      assert %{
               "error" => "invalid_client",
               "error_description" => "client_secret: does not match expected value"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 redirect_uri: seeds.grant.redirect_uri,
                 client_id: seeds.client.id,
                 client_secret: "boom"
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "req body client id/secret are ignored in presence of valid auth header", seeds do
      basic_auth = Plug.BasicAuth.encode_basic_auth(seeds.client.id, seeds.client.secret)

      conn(:post, "/", %{
        grant_type: "authorization_code",
        code: seeds.grant.code,
        client_id: Ecto.UUID.generate(),
        client_secret: "test",
        redirect_uri: seeds.grant.redirect_uri
      })
      |> put_req_header("authorization", basic_auth)
      |> TokenEndpoint.call(seeds.opts)
      |> assert_dont_cache()
      |> json_response(200)
    end

    test "req body client id/secret are ignored in presence of invalid auth header", seeds do
      assert "auth_header: invalid HTTP basic authentication" ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 redirect_uri: seeds.grant.redirect_uri
               })
               |> put_req_header("authorization", "BOOM")
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> assert_status(401)
               |> assert_resp_headers(%{"www-authenticate" => "Basic"})
               |> Map.get(:resp_body)
    end

    test "invalid basic auth client secret results in 401", seeds do
      basic_auth = Plug.BasicAuth.encode_basic_auth(seeds.client.id, "boom")

      assert "auth_header: is invalid, client_secret: does not match expected value" ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 redirect_uri: seeds.grant.redirect_uri
               })
               |> put_req_header("authorization", basic_auth)
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> assert_status(401)
               |> assert_resp_headers(%{"www-authenticate" => "Basic"})
               |> Map.get(:resp_body)
    end

    test "invalid basic auth client id results in 401", seeds do
      basic_auth = Plug.BasicAuth.encode_basic_auth("BOOM", seeds.client.secret)

      assert "auth_header: is invalid, client_id: is invalid" ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 redirect_uri: seeds.grant.redirect_uri
               })
               |> put_req_header("authorization", basic_auth)
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> assert_status(401)
               |> assert_resp_headers(%{"www-authenticate" => "Basic"})
               |> Map.get(:resp_body)
    end

    test "correct client_secret is required for confidential clients", seeds do
      assert %{
               "error" => "invalid_client",
               "error_description" => "client_secret: can't be blank"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 redirect_uri: seeds.grant.redirect_uri
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)

      assert %{
               "error" => "invalid_client",
               "error_description" => "client_secret: does not match expected value"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 redirect_uri: seeds.grant.redirect_uri,
                 client_secret: "wrong"
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end
  end

  describe "authorization_code flow" do
    test "code is required", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" => "code: can't be blank"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "grant must be found", seeds do
      assert %{"error" => "invalid_grant", "error_description" => "code: not found"} ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: "not findable",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "grant must not have expired", seeds do
      past = DateTime.utc_now() |> DateTime.add(-10) |> DateTime.truncate(:second)
      seeds.grant |> change(%{expires_at: past}) |> Repo.update!()

      assert %{"error" => "invalid_grant", "error_description" => "code: expired"} ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "client_id must match the code's grant", seeds do
      other_client = insert_test_client()

      assert %{
               "error" => "invalid_grant",
               "error_description" => "client_id: does not match code"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: other_client.id,
                 client_secret: other_client.secret,
                 redirect_uri: seeds.grant.redirect_uri
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "grant type must be enabled for client", seeds do
      assert {:ok, _} = Clients.update(seeds.client, %{grant_types: ~w(refresh_token)})

      assert %{
               "error" => "unauthorized_client",
               "error_description" => "grant_type: unsupported by client"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 redirect_uri: seeds.grant.redirect_uri
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "redirect_uri is required if it was specified when calling 'authorize'", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" => "redirect_uri: can't be blank"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)

      seeds.grant |> change(%{redirect_uri_is_default: true}) |> Repo.update!()

      conn(:post, "/", %{
        grant_type: "authorization_code",
        code: seeds.grant.code,
        client_id: seeds.client.id,
        client_secret: seeds.client.secret
      })
      |> TokenEndpoint.call(seeds.opts)
      |> assert_dont_cache()
      |> json_response(200)
    end

    test "redirect_uri must match grant when specified", seeds do
      assert %{
               "error" => "invalid_grant",
               "error_description" => "redirect_uri: does not match grant"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 redirect_uri: "https://wrong"
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)

      seeds.grant |> change(%{redirect_uri_is_default: true}) |> Repo.update!()

      assert %{
               "error" => "invalid_grant",
               "error_description" => "redirect_uri: does not match grant"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 redirect_uri: "https://wrong"
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "(PKCE) code_verifier is required if code_challenge was specified", seeds do
      verifier = "test!"
      challenge = :crypto.hash(:sha256, verifier) |> url_encode()
      seeds.grant |> change(%{code_challenge: challenge}) |> Repo.update!()

      assert %{
               "error" => "invalid_request",
               "error_description" => "code_verifier: can't be blank"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 redirect_uri: seeds.grant.redirect_uri,
                 client_secret: seeds.client.secret
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "(PKCE) code_verifier must match code_challenge", seeds do
      verifier = "test!"
      challenge = :crypto.hash(:sha256, verifier) |> url_encode()
      seeds.grant |> change(%{code_challenge: challenge}) |> Repo.update!()

      assert %{
               "error" => "invalid_request",
               "error_description" => "code_verifier: does not match expected value"
             } ==
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 redirect_uri: seeds.grant.redirect_uri,
                 client_secret: seeds.client.secret,
                 code_verifier: "invalid"
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "(PKCE) works with valid code", seeds do
      verifier = "test!"
      challenge = :crypto.hash(:sha256, verifier) |> url_encode()
      seeds.grant |> change(%{code_challenge: challenge}) |> Repo.update!()

      conn(:post, "/", %{
        grant_type: "authorization_code",
        code: seeds.grant.code,
        client_id: seeds.client.id,
        redirect_uri: seeds.grant.redirect_uri,
        client_secret: seeds.client.secret,
        code_verifier: verifier
      })
      |> TokenEndpoint.call(seeds.opts)
      |> assert_dont_cache()
      |> json_response(200)
    end

    test "grant is deleted so that code is single-use", seeds do
      conn(:post, "/", %{
        grant_type: "authorization_code",
        code: seeds.grant.code,
        client_id: seeds.client.id,
        redirect_uri: seeds.grant.redirect_uri,
        client_secret: seeds.client.secret
      })
      |> TokenEndpoint.call(seeds.opts)
      |> assert_dont_cache()
      |> json_response(200)

      refute Grants.get_by(id: seeds.grant.id)
    end

    test "response body checks out, bearer tokens, cid, uid, scope, styp correct", seeds do
      assert %{
               "access_token" => a_token,
               "refresh_token" => r_token,
               "scope" => "read",
               "token_type" => "bearer",
               "expires_in" => _,
               "refresh_expires_in" => _
             } =
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 redirect_uri: seeds.grant.redirect_uri,
                 client_secret: seeds.client.secret
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(200)

      cid = seeds.client.id
      uid = seeds.user.id

      assert {:ok,
              %{
                "cid" => ^cid,
                "exp" => _,
                "iat" => _,
                "iss" => "stuff",
                "jti" => <<_::binary>>,
                "nbf" => _,
                "scope" => ["read"],
                "sid" => <<_::binary>>,
                "styp" => "oauth2",
                "sub" => ^uid,
                "type" => "access"
              }} = Charon.TokenFactory.verify(a_token, @config)

      assert {:ok,
              %{
                "cid" => ^cid,
                "exp" => _,
                "iat" => _,
                "iss" => "stuff",
                "jti" => <<_::binary>>,
                "nbf" => _,
                "scope" => ["read"],
                "sid" => <<_::binary>>,
                "styp" => "oauth2",
                "sub" => ^uid,
                "type" => "refresh"
              }} = Charon.TokenFactory.verify(r_token, @config)
    end

    test "upsert_session call may be customized", seeds do
      mod_conf = seeds.opts.mod_conf

      override = fn [conn, config, opts] ->
        opts = put_in(opts[:access_claim_overrides]["scope"], "test")
        [conn, config, opts]
      end

      mod_conf = %{mod_conf | customize_session_upsert_args: override}
      opts = %{seeds.opts | mod_conf: mod_conf}

      assert %{"access_token" => a_token} =
               conn(:post, "/", %{
                 grant_type: "authorization_code",
                 code: seeds.grant.code,
                 client_id: seeds.client.id,
                 redirect_uri: seeds.grant.redirect_uri,
                 client_secret: seeds.client.secret
               })
               |> TokenEndpoint.call(opts)
               |> assert_dont_cache()
               |> json_response(200)

      assert {:ok, %{"scope" => "test"}} = Charon.TokenFactory.verify(a_token, @config)
    end
  end

  describe "refresh_token flow" do
    test "refresh_token is required", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" => "refresh_token: can't be blank"
             } ==
               conn(:post, "/", %{
                 grant_type: "refresh_token",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "grant type must be enabled for client", seeds do
      assert {:ok, _} = Clients.update(seeds.client, %{grant_types: ~w(authorization_code)})

      assert %{
               "error" => "unauthorized_client",
               "error_description" => "grant_type: unsupported by client"
             } ==
               conn(:post, "/", %{
                 grant_type: "refresh_token",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 refresh_token: "test"
               })
               |> TokenEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "refresh_token must be valid", seeds do
      verify_token = fn conn, _config ->
        set_auth_error(conn, "BOOM")
      end

      config = override_opt_mod_conf(@config, CharonOauth2, verify_refresh_token: verify_token)
      opts = TokenEndpoint.init(config: config)

      assert %{
               "error" => "invalid_grant",
               "error_description" => "refresh_token: BOOM"
             } ==
               conn(:post, "/", %{
                 grant_type: "refresh_token",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 refresh_token: "test"
               })
               |> TokenEndpoint.call(opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "refresh_token client_id must match", seeds do
      verify_token = fn conn, _config ->
        set_token_payload(conn, %{"sub" => 1, "cid" => Ecto.UUID.generate()})
      end

      config = override_opt_mod_conf(@config, CharonOauth2, verify_refresh_token: verify_token)
      opts = TokenEndpoint.init(config: config)

      assert %{
               "error" => "invalid_grant",
               "error_description" => "client_id: does not match refresh token"
             } ==
               conn(:post, "/", %{
                 grant_type: "refresh_token",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 refresh_token: "test"
               })
               |> TokenEndpoint.call(opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "authorization must exist", seeds do
      verify_token = fn conn, _config ->
        set_token_payload(conn, %{"sub" => 1, "cid" => seeds.client.id})
      end

      config = override_opt_mod_conf(@config, CharonOauth2, verify_refresh_token: verify_token)
      opts = TokenEndpoint.init(config: config)

      assert %{"error" => "invalid_grant", "error_description" => "authorization: not found"} ==
               conn(:post, "/", %{
                 grant_type: "refresh_token",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 refresh_token: "test"
               })
               |> TokenEndpoint.call(opts)
               |> assert_dont_cache()
               |> json_response(400)
    end

    test "works", seeds do
      verify_token = fn conn, _config ->
        conn
        |> set_token_payload(%{"sub" => seeds.user.id, "cid" => seeds.client.id})
        |> set_session(%Session{
          created_at: 1,
          expires_at: 1,
          id: 1,
          refresh_expires_at: 1,
          refresh_tokens_at: 1,
          refresh_tokens: [],
          refreshed_at: 1,
          user_id: seeds.user.id
        })
      end

      config = override_opt_mod_conf(@config, CharonOauth2, verify_refresh_token: verify_token)
      opts = TokenEndpoint.init(config: config)

      assert %{"access_token" => _} =
               conn(:post, "/", %{
                 grant_type: "refresh_token",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 refresh_token: "test"
               })
               |> TokenEndpoint.call(opts)
               |> assert_dont_cache()
               |> json_response(200)
    end

    test "authorization's current scope is granted, regardless of token or request scope",
         seeds do
      verify_token = fn conn, _config ->
        conn
        |> set_token_payload(%{
          "sub" => seeds.user.id,
          "cid" => seeds.client.id,
          "scope" => ["boom"]
        })
        |> set_session(%Session{
          created_at: 1,
          expires_at: 1,
          id: 1,
          refresh_expires_at: 1,
          refresh_tokens_at: 1,
          refresh_tokens: [],
          refreshed_at: 1,
          user_id: seeds.user.id
        })
      end

      config = override_opt_mod_conf(@config, CharonOauth2, verify_refresh_token: verify_token)
      opts = TokenEndpoint.init(config: config)

      assert %{"scope" => "read"} =
               conn(:post, "/", %{
                 grant_type: "refresh_token",
                 client_id: seeds.client.id,
                 client_secret: seeds.client.secret,
                 refresh_token: "test",
                 scope: "boom"
               })
               |> TokenEndpoint.call(opts)
               |> assert_dont_cache()
               |> json_response(200)
    end
  end
end
