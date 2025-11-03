# Client Credentials Flow Implementation Guide for CharonOauth2

## Table of Contents

- [Overview](#overview)
- [What is Client Credentials Flow?](#what-is-client-credentials-flow)
- [Current State of CharonOauth2](#current-state-of-charonoauth2)
- [Key Differences from Authorization Code Flow](#key-differences-from-authorization-code-flow)
- [Implementation Requirements](#implementation-requirements)
  - [1. Token Validator Changes](#1-token-validator-changes)
  - [2. Token Endpoint Changes](#2-token-endpoint-changes)
  - [3. Client Schema Changes](#3-client-schema-changes)
- [Key Design Decisions](#key-design-decisions)
- [Usage Examples](#usage-examples)
- [Testing Considerations](#testing-considerations)
- [Summary](#summary)

## Overview

This document outlines how to implement the OAuth2 Client Credentials flow in CharonOauth2. The client credentials grant is designed for machine-to-machine (M2M) authentication where no user is involved.

## What is Client Credentials Flow?

The **client credentials grant** is an OAuth2 flow designed for **machine-to-machine (M2M) authentication** where:

- **No user is involved** (2-legged OAuth, not 3-legged)
- The client application authenticates using its own credentials (client_id + client_secret)
- The resulting access token represents the client itself, not a user
- Typically used for backend services, APIs calling APIs, scheduled jobs, etc.

### OAuth2 Spec Reference

[RFC 6749 Section 4.4](https://datatracker.ietf.org/doc/html/rfc6749#section-4.4)

## Current State of CharonOauth2

CharonOauth2 currently supports only:

1. **Authorization Code Grant** (with PKCE) - for user authorization
2. **Refresh Token Grant** - for renewing access tokens

The codebase is structured to make adding new grant types straightforward through:
- Request validation in `lib/charon_oauth2/internal/req_validators/token_validator.ex`
- Grant processing in `lib/charon_oauth2/internal/gen_mod/plugs/token_endpoint.ex`
- Client configuration in `lib/charon_oauth2/internal/gen_mod/client.ex`

## Key Differences from Authorization Code Flow

| Aspect | Authorization Code | Client Credentials |
|--------|-------------------|-------------------|
| User involvement | Required (user grants permission) | None (service-to-service) |
| Resource owner | User (resource_owner_id) | Client itself (no resource owner) |
| Redirect URI | Required | Not needed |
| Authorization endpoint | Used | **Not used** |
| Token endpoint | Used | Used |
| Refresh tokens | Typically issued | Optional (often not issued) |
| Scope | User-granted permissions | Client's own permissions |
| PKCE | Required | Not applicable |
| Grants table | Used | **Not used** |

## Implementation Requirements

### 1. Token Validator Changes

**File:** `lib/charon_oauth2/internal/req_validators/token_validator.ex`

#### Step 1: Update Grant Types List (Line 26)

```elixir
@grant_types ~w(authorization_code refresh_token client_credentials)
```

#### Step 2: Add Validation Functions (After line 140)

```elixir
@doc """
For the client credentials flow, we verify that the client supports the grant type.
Optionally, scope can be requested (must be subset of client's allowed scope).

https://datatracker.ietf.org/doc/html/rfc6749#section-4.4.2
"""
@spec client_credentials_flow_step_1(Changeset.t()) :: Changeset.t()
def client_credentials_flow_step_1(cs) do
  client = cs.changes.client
  cs |> validate_client_grant_type(client)
end

@doc """
After authentication, verify that requested scope is subset of client's scope.
If no scope is requested, the client's full scope will be used.
"""
@spec client_credentials_flow_step_2(Changeset.t()) :: Changeset.t()
def client_credentials_flow_step_2(cs) do
  # If scope parameter is present, validate it's a subset of client's scope
  # If not present, we'll use the client's full scope in the token endpoint
  case Map.get(cs.changes, :scope) do
    nil -> cs
    _scope ->
      client = cs.changes.client
      validate_ordset_contains(cs, :scope, client.scope,
        "client allowed #{Enum.join(client.scope, ", ")}")
  end
end
```

### 2. Token Endpoint Changes

**File:** `lib/charon_oauth2/internal/gen_mod/plugs/token_endpoint.ex`

#### Add New `process_grant` Clause (After line 232)

```elixir
# https://datatracker.ietf.org/doc/html/rfc6749#section-4.4
defp process_grant(
       cs = %{changes: %{client: client, grant_type: "client_credentials"}},
       conn,
       opts
     ) do
  with cs = %{valid?: true} <- Validate.client_credentials_flow_step_1(cs),
       cs = %{valid?: true} <- Validate.client_credentials_flow_step_2(cs) do
    # Use requested scope (if valid) or client's full scope
    scopes = Map.get(cs.changes, :scope, client.scope)
    now = now()

    # Create a "synthetic" authorization for the client itself
    # Note: resource_owner_id is the client's owner (the user who registered the client)
    synthetic_auth = %{
      client_id: client.id,
      resource_owner_id: client.owner_id,
      scope: scopes
    }

    conn
    |> upsert_session(synthetic_auth, scopes, opts,
         user_id: client.owner_id)
    |> send_token_response(scopes, now, opts)
  else
    invalid_cs ->
      error_map = changeset_errors_to_map(invalid_cs)
      descr = error_map |> cs_error_map_to_string()

      error_map
      |> case do
        %{grant_type: ["unsupported by client"]} ->
          json_error(conn, 400, "unauthorized_client", descr, opts)

        %{scope: ["client allowed " <> _]} ->
          json_error(conn, 400, "invalid_scope", descr, opts)

        _other ->
          json_error(conn, 400, "invalid_request", descr, opts)
      end
  end
end
```

### 3. Client Schema Changes

**File:** `lib/charon_oauth2/internal/gen_mod/client.ex`

#### Update Grant Types List (Line 45)

```elixir
@grant_types ~w(authorization_code refresh_token client_credentials)
             |> :ordsets.from_list()
```

## Key Design Decisions

### Decision 1: Refresh Tokens

**Should client credentials flow issue refresh tokens?**

**Options:**
- Issue refresh tokens (allows token renewal without re-authentication)
- Don't issue refresh tokens (simpler, client can just request new token with credentials)

**Recommendation:** **Don't issue refresh tokens** for client credentials flow because:
- The client credentials themselves are long-lived (the secret doesn't expire)
- Clients can easily request a new access token at any time using their credentials
- Reduces complexity and attack surface
- Follows common industry practice

**If you want to support this:** Modify the `upsert_session` call to skip refresh token generation:
```elixir
# Add option to skip refresh token
upsert_opts = [skip_refresh_token: true]
conn
|> upsert_session(synthetic_auth, scopes, opts,
     [user_id: client.owner_id] ++ upsert_opts)
```

### Decision 2: Resource Owner ID

**What should be the `resource_owner_id` in the token?**

**Options:**

1. **Use `client.owner_id`** (the user who created/registered the OAuth2 client)
   - Pro: Maintains association with a user account
   - Pro: Existing authorization logic might work
   - Con: Might grant unintended user-level permissions

2. **Use `nil` or special marker** like `"client:#{client.id}"`
   - Pro: Clearly distinguishes client credentials tokens from user tokens
   - Pro: Prevents accidental privilege escalation
   - Con: Requires updates to authorization logic

3. **Use `client.id` itself**
   - Pro: Simple and clear
   - Con: Type mismatch if resource_owner_id expects user IDs

**Recommendation:** **Option 1** (`client.owner_id`) is implemented above because:
- It maintains compatibility with existing session/token infrastructure
- The `scope` claim already restricts what the token can do
- Resource ownership can be tracked for audit purposes

**Important:** Ensure your authorization logic checks the `scope` claim to differentiate between user sessions and client credentials sessions!

### Decision 3: Scope Handling

**How should scopes be determined?**

**Implementation:**
- Client credentials tokens use the **client's configured scope** by default
- Optionally allow `scope` parameter in request (must be subset of client's scope)
- This follows the OAuth2 spec recommendation

**Configuration:**
When creating a client with client credentials grant type:
```elixir
MyApp.CharonOauth2.Clients.insert(%{
  owner_id: some_user_id,
  client_type: "confidential",
  grant_types: ["client_credentials"],
  scope: ["api:read", "api:write", "service:admin"],  # What this client can do
  redirect_uris: []  # Not needed for client credentials
})
```

### Decision 4: Token Lifetime

**Considerations:**
- Client credentials tokens might need different TTL than user tokens
- Since there's no user session expiry concern, tokens could be shorter-lived
- Balance between security (shorter) and performance (fewer token requests)

**Implementation Options:**
1. Use existing session_ttl configuration (simplest)
2. Add new `client_credentials_token_ttl` config option
3. Make it configurable per-client

**Recommendation:** Start with option 1 (existing configuration) and add per-client configuration later if needed.

## Usage Examples

### Example 1: Basic Client Credentials Request (HTTP Basic Auth)

```bash
curl -X POST https://your-api.com/api/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "CLIENT_ID:CLIENT_SECRET" \
  -d "grant_type=client_credentials"
```

### Example 2: With Body Parameters

```bash
curl -X POST https://your-api.com/api/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=CLIENT_ID" \
  -d "client_secret=CLIENT_SECRET"
```

### Example 3: With Scope Parameter

```bash
curl -X POST https://your-api.com/api/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "CLIENT_ID:CLIENT_SECRET" \
  -d "grant_type=client_credentials" \
  -d "scope=api:read api:write"
```

### Example 4: Response

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_in": 3600,
  "refresh_expires_in": 86400,
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "scope": "api:read api:write",
  "token_type": "bearer"
}
```

### Token Claims

The resulting access token will contain:
```json
{
  "sub": "user-id-who-owns-client",  // or client.owner_id
  "cid": "client-id",                // OAuth2 client ID
  "scope": ["api:read", "api:write"], // Ordered set
  "iat": 1234567890,
  "exp": 1234571490,
  // ... other standard claims
}
```

## Testing Considerations

### 1. Update Test Seeds

**File:** `lib/charon_oauth2/internal/gen_mod/test_seeds.ex`

Add support for creating clients with `client_credentials` grant type:

```elixir
def client_credentials_client(opts \\ []) do
  %{
    client_type: "confidential",
    grant_types: ["client_credentials"],
    scope: opts[:scope] || ["api:read", "api:write"],
    redirect_uris: [],  # Not needed
    owner_id: opts[:owner_id] || create_user().id
  }
  |> insert_client()
end
```

### 2. Test Cases to Add

Create tests in `test/charon_oauth2/plugs/token_endpoint_test.exs`:

1. **Successful token request** with valid client credentials
2. **Invalid client credentials** returns `invalid_client` error
3. **Unsupported grant type** for client returns `unauthorized_client`
4. **Scope parameter validation**:
   - Valid subset of client scope → success
   - Scope exceeds client scope → `invalid_scope` error
   - No scope parameter → uses client's full scope
5. **Public clients** attempting client credentials flow
6. **Token claims verification** (correct `sub`, `cid`, `scope`)
7. **HTTP Basic vs body parameters** authentication
8. **Token usage** - verify tokens work for API access

### 3. Integration Testing

Test a complete flow:
```elixir
test "client credentials flow - complete example" do
  # Create a confidential client with client_credentials grant
  client = client_credentials_client(scope: ["api:read", "api:write"])

  # Request token
  conn = post(build_conn(), "/api/oauth2/token", %{
    "grant_type" => "client_credentials",
    "client_id" => client.id,
    "client_secret" => client.secret,
    "scope" => "api:read"
  })

  assert %{"access_token" => access_token, "scope" => "api:read"} =
         json_response(conn, 200)

  # Use token to access API
  conn = build_conn()
    |> put_req_header("authorization", "Bearer #{access_token}")
    |> get("/api/some-protected-resource")

  assert response(conn, 200)
end
```

## Summary

The client credentials flow is **simpler** than authorization code flow because:

### What's NOT Needed:
- ❌ No user authorization page needed
- ❌ No authorization endpoint interaction
- ❌ No grants table entries
- ❌ No PKCE validation
- ❌ No redirect URIs
- ❌ No user consent flow

### What IS Needed:
- ✅ Client authentication (via HTTP Basic or body parameters)
- ✅ Direct token issuance after client authentication
- ✅ Client's scope becomes the token scope
- ✅ Token endpoint modifications only

### Core Files to Modify:

1. `lib/charon_oauth2/internal/req_validators/token_validator.ex`
   - Add `client_credentials` to grant types list
   - Add validation functions

2. `lib/charon_oauth2/internal/gen_mod/plugs/token_endpoint.ex`
   - Add `process_grant` clause for client credentials

3. `lib/charon_oauth2/internal/gen_mod/client.ex`
   - Add `client_credentials` to allowed grant types

### Use Cases:

Perfect for:
- Backend service authentication
- Microservice-to-microservice communication
- Scheduled jobs/cron tasks accessing APIs
- Server-side applications with no user context
- API gateways authenticating to upstream services

### Security Considerations:

- Client secret must be kept secure (use confidential clients only)
- Scopes should be carefully designed to limit client permissions
- Consider shorter token lifetimes for high-security scenarios
- Monitor and log client credentials usage for auditing
- Rotate client secrets periodically

---

## Next Steps

1. Implement the changes outlined in this document
2. Add comprehensive test coverage
3. Update documentation to include client credentials flow
4. Consider adding configuration options for:
   - Per-client token TTL
   - Refresh token generation toggle
   - Scope validation strictness
5. Update migration scripts if needed for new grant type
6. Update API documentation with usage examples

## References

- [RFC 6749 - OAuth 2.0 Authorization Framework](https://datatracker.ietf.org/doc/html/rfc6749)
- [RFC 6749 Section 4.4 - Client Credentials Grant](https://datatracker.ietf.org/doc/html/rfc6749#section-4.4)
- [OAuth 2.1 Draft Spec](https://www.ietf.org/archive/id/draft-ietf-oauth-v2-1-07.html)
- [Charon Documentation](https://github.com/weareyipyip/charon)
- [CharonOauth2 Documentation](https://hexdocs.pm/charon_oauth2)
