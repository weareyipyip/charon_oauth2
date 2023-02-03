defmodule CharonOauth2.Plugs.AuthorizationEndpointTest do
  use CharonOauth2.DataCase
  alias MyApp.CharonOauth2.{Authorizations, Grants, Plugs.AuthorizationEndpoint, Config}
  import MyApp.{Seeds, TestUtils}
  import Plug.Test
  import Charon.TestHelpers

  @config Config.get()

  setup do
    client = insert_test_client()
    opts = AuthorizationEndpoint.init(config: @config)
    user = insert_test_user()
    [client: client, opts: opts, user: user]
  end

  describe "call/2" do
    test "returns 404 for other method/path", seeds do
      assert %{status: 404} =
               conn(:get, "/") |> AuthorizationEndpoint.call(seeds.opts) |> assert_dont_cache()

      assert %{status: 404} =
               conn(:post, "/tset")
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
    end

    test "missing client id results in JSON error response (no redirect)", seeds do
      assert %{"client_id" => ["can't be blank"]} ==
               conn(:post, "/", %{
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
               |> get_in(~w(errors))
    end

    test "malformed client id results in JSON error response (no redirect)", seeds do
      assert %{"client_id" => ["is invalid"]} ==
               conn(:post, "/", %{
                 client_id: "a",
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
               |> get_in(~w(errors))
    end

    test "unknown client id results in JSON error response (no redirect)", seeds do
      assert %{"client_id" => ["client not found"]} ==
               conn(:post, "/", %{
                 client_id: Ecto.UUID.generate(),
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
               |> get_in(~w(errors))
    end

    test "redirect_uri not required for client with a single redirect_uri", seeds do
      conn(:post, "/", %{
        client_id: seeds.client.id,
        response_type: "code",
        permission_granted: true,
        scope: "read",
        state: "teststate"
      })
      |> login(seeds)
      |> AuthorizationEndpoint.call(seeds.opts)
      |> assert_dont_cache()
      # redirect means no redirect_uri error
      |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "redirect_uri required for client with multiple redirect_uris", seeds do
      client = insert_test_client(redirect_uris: ~w(https://a https://b))

      assert %{"redirect_uri" => ["can't be blank"]} ==
               conn(:post, "/", %{
                 client_id: client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
               |> get_in(~w(errors))
    end

    test "redirect_uri must match client if provided", seeds do
      assert %{"redirect_uri" => ["invalid entry"]} ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 redirect_uri: "https://a",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
               |> get_in(~w(errors))
    end

    test "response_type must be configured for client", seeds do
      client = insert_test_client(grant_types: ~w(refresh_token))

      assert %{
               "error" => "unauthorized_client",
               "error_description" => "response_type: not supported by client",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "state is optional", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" => "response_type: not recognized"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "codez",
                 permission_granted: true,
                 scope: "read"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "response_type must be set", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" => "response_type: can't be blank",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "response_type and code_challenge_method must be recognized", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" =>
                 "code_challenge_method: not recognized, response_type: not recognized",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "boom",
                 permission_granted: true,
                 scope: "read",
                 code_challenge_method: "tset",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "params must be valid", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" =>
                 "code_challenge: is invalid, code_challenge_method: is invalid, response_type: is invalid, scope: is invalid, state: is invalid"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: 1,
                 scope: 1,
                 state: 1,
                 code_challenge: [],
                 code_challenge_method: [],
                 permission_granted: 1
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "permission_granted must be set by our own client (JSON 400 resp)", seeds do
      assert %{"permission_granted" => ["can't be blank"]} ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
               |> get_in(~w(errors))
    end

    test "permission_granted must be valid (JSON 400 resp)", seeds do
      assert %{"permission_granted" => ["is invalid"]} ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 scope: "read",
                 permission_granted: 1,
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> json_response(400)
               |> get_in(~w(errors))
    end

    test "permission_granted must be true", seeds do
      assert %{
               "error" => "access_denied",
               "error_description" => "permission_granted: no",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: false,
                 scope: "read",
                 state: "teststate",
                 code_challenge: "test",
                 code_challenge_method: "S256"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "scope must be enabled for client", seeds do
      assert %{
               "error" => "access_denied",
               "error_description" => "scope: client supports read",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "write",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "scope must be known", seeds do
      assert %{
               "error" => "invalid_scope",
               "error_description" => "scope: known scopes are party, read, write",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "writez",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end
  end

  describe "authorization_code flow" do
    test "scope must be set for a new authorization", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" => "scope: can't be blank",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 state: "teststate",
                 code_challenge: "test",
                 code_challenge_method: "S256"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "new authorization is created with requested params", seeds do
      assert %{"code" => _, "state" => "teststate"} =
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate",
                 code_challenge: "test",
                 code_challenge_method: "S256"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())

      uid = seeds.user.id
      cid = seeds.client.id

      assert [%{scope: ~w(read), resource_owner_id: ^uid, client_id: ^cid}] = Authorizations.all()
    end

    test "scope is not required for an existing authorization", seeds do
      insert_test_authorization(client_id: seeds.client.id, resource_owner_id: seeds.user.id)

      assert %{"code" => _, "state" => "teststate"} =
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 state: "teststate",
                 code_challenge: "test",
                 code_challenge_method: "S256"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "existing authorization's scope is expanded to request scope", seeds do
      client = insert_test_client(scope: ~w(read write))

      insert_test_authorization(
        client_id: client.id,
        resource_owner_id: seeds.user.id,
        scope: ~w(read)
      )

      assert %{"code" => _, "state" => "teststate"} =
               conn(:post, "/", %{
                 client_id: client.id,
                 response_type: "code",
                 permission_granted: true,
                 state: "teststate",
                 scope: "write",
                 code_challenge: "test",
                 code_challenge_method: "S256"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())

      assert [%{scope: ~w(write)}] = Authorizations.all()
    end

    test "existing authorization's scope is NOT reduced to request scope", seeds do
      client = insert_test_client(scope: ~w(read write))

      insert_test_authorization(
        client_id: client.id,
        resource_owner_id: seeds.user.id,
        scope: ~w(read write)
      )

      assert %{"code" => _, "state" => "teststate"} =
               conn(:post, "/", %{
                 client_id: client.id,
                 response_type: "code",
                 permission_granted: true,
                 state: "teststate",
                 scope: "write",
                 code_challenge: "test",
                 code_challenge_method: "S256"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())

      assert [%{scope: ~w(read write)}] = Authorizations.all()
    end

    test "new grant is created for authorization / user", seeds do
      uid = seeds.user.id
      cid = seeds.client.id
      auth = insert_test_authorization(client_id: cid, resource_owner_id: uid)
      aid = auth.id
      [redir_uri] = seeds.client.redirect_uris

      assert %{"code" => code, "state" => "teststate"} =
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 state: "teststate",
                 code_challenge: "test",
                 code_challenge_method: "S256"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())

      assert %{
               authorization_id: ^aid,
               resource_owner_id: ^uid,
               type: "authorization_code",
               redirect_uri: ^redir_uri,
               redirect_uri_specified: false
             } = Grants.get_by(code: code)
    end

    test "request redirect_uri is set in grant and used for redir", seeds do
      client = insert_test_client(redirect_uris: ~w(https://a https://b))

      assert %{"code" => code, "state" => "teststate"} =
               conn(:post, "/", %{
                 client_id: client.id,
                 response_type: "code",
                 permission_granted: true,
                 state: "teststate",
                 redirect_uri: "https://b",
                 code_challenge: "test",
                 code_challenge_method: "S256",
                 scope: "read"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response("https://b")

      assert %{redirect_uri: "https://b", redirect_uri_specified: true} =
               Grants.get_by(code: code)
    end
  end

  describe "authorization_code with PKCE flow" do
    test "PKCE is required for ALL clients by default", seeds do
      assert %{
               "state" => "teststate",
               "error" => "invalid_request",
               "error_description" =>
                 "code_challenge: can't be blank (PKCE is required), code_challenge_method: can't be blank"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "PKCE is required for public clients if :enforce_pkce = :public", seeds do
      config = override_opt_mod_conf(@config, CharonOauth2, enforce_pkce: :public)
      opts = AuthorizationEndpoint.init(config: config)

      public_client = insert_test_client(client_type: "public")

      assert %{
               "state" => "teststate",
               "error" => "invalid_request",
               "error_description" =>
                 "code_challenge: can't be blank (PKCE is required), code_challenge_method: can't be blank"
             } ==
               conn(:post, "/", %{
                 client_id: public_client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())

      # not required for confidential client
      assert %{"code" => _} =
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "PKCE is not required if :enforce_pkce = :no", seeds do
      config = override_opt_mod_conf(@config, CharonOauth2, enforce_pkce: :no)
      opts = AuthorizationEndpoint.init(config: config)

      public_client = insert_test_client(client_type: "public")

      assert %{"code" => _} =
               conn(:post, "/", %{
                 client_id: public_client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())

      # not required for confidential client
      assert %{"code" => _} =
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "code_challenge_method is required and must be S256 if code_challenge is set", seeds do
      assert %{
               "error" => "invalid_request",
               "error_description" => "code_challenge_method: can't be blank",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 code_challenge: "test",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())

      assert %{
               "error" => "invalid_request",
               "error_description" => "code_challenge_method: is unsupported",
               "state" => "teststate"
             } ==
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 code_challenge: "test",
                 code_challenge_method: "plain",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())
    end

    test "code challenge is stored in grant for token endpoint", seeds do
      assert %{"code" => code, "state" => "teststate"} =
               conn(:post, "/", %{
                 client_id: seeds.client.id,
                 response_type: "code",
                 permission_granted: true,
                 scope: "read",
                 code_challenge: "test",
                 code_challenge_method: "S256",
                 state: "teststate"
               })
               |> login(seeds)
               |> AuthorizationEndpoint.call(seeds.opts)
               |> assert_dont_cache()
               |> redir_response(seeds.client.redirect_uris |> List.first())

      assert %{code_challenge: "test"} = Grants.get_by(code: code)
    end
  end
end
