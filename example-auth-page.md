# Example authorization page (React)

```tsx
import React from "react";

import ApiService from "@apiService";
import { Oauth2Client } from "@types";
import { useAppContext } from "@global/context";
import { Button } from "@components/atoms/Button/Component";

export default function AuthorizeOauth2(): JSX.Element {
  let params = Object.fromEntries(
    new URLSearchParams(window.location.search).entries()
  );

  const { setErrorMessage } = useAppContext();

  const [scopeDescriptions, setScopeDescriptions] = React.useState<{
    [key: string]: string;
  }>({});
  const [authorizedScopes, setAuthorizedScopes] = React.useState<string[]>([]);
  const [newScopes, setNewScopes] = React.useState<string[]>([]);
  const [client, setClient] = React.useState<Oauth2Client | null>(null);

  React.useEffect((): void => {
    const clientId = params.client_id;
    const scopes = params.scope?.split(" ") ?? [];

    if (clientId) {
      fetchData(clientId, scopes).catch((error) => {
        setErrorMessage("Something went wrong");
        throw error;
      });
    }
  }, [params]);

  const fetchData = async (
    clientId: string,
    scopes: string[]
  ): Promise<void> => {
    const [
      {
        data: {
          data: { oauth2_client: client },
        },
      },
      {
        data: {
          data: { oauth2_authorizations: authorizations },
        },
      },
      {
        data: {
          data: { token_scopes: scopeDescriptions },
        },
      },
    ] = await Promise.all([
      ApiService.oauth2Clients.show(clientId),
      ApiService.my.oauth2Authorizations.list({ client_id: clientId }),
      ApiService.tokenScopes.list(),
    ]);

    // If specific scopes are requested, we'll use those. Otherwise, default to all client scopes.
    const requestedScopes = scopes.length > 0 ? scopes : client.scopes;
    const authorizedScopes = authorizations?.[0]?.scope ?? [];
    const newScopes = requestedScopes.filter(
      (s) => !authorizedScopes.includes(s)
    );

    if (newScopes.length === 0) {
      // If all requested scopes are already authorized, we can just re-authorize on behalf of the user.
      await authorize(true);
      return;
    }

    setClient(client);
    setScopeDescriptions(scopeDescriptions);
    setAuthorizedScopes(authorizedScopes);
    setNewScopes(newScopes);
  };

  const authorize = async (grantPermission: boolean): Promise<void> => {
    try {
      const {
        data: { redirect_to: redirectTo },
      } = await ApiService.oauth2.authorize({
        ...params,
        permission_granted: grantPermission,
      });
      window.location.replace(redirectTo);
    } catch (error: any) {
      setErrorMessage(JSON.stringify(error.response.data));
    }
  };

  if (!client) {
    return <div>Loading...</div>;
  } else {
    return (
      <div>
        <div>
          <div>
            <p>
              The following app wishes to use your account on your behalf:{" "}
              <strong>{client.name}</strong> - {client.description}
            </p>
            <br />

            {authorizedScopes.length > 0 && (
              <>
                <p>You have already granted {client.name} permission to:</p>
                <ul>
                  {authorizedScopes.map((scope: string, i: number) => (
                    <li key={i}>{scopeDescriptions[scope] ?? scope}</li>
                  ))}
                </ul>
              </>
            )}

            <p>In addition, {client.name} wants to:</p>
            <ul>
              {newScopes.map((scope: string, i: number) => (
                <li key={i}>{scopeDescriptions[scope] ?? scope}</li>
              ))}
            </ul>
          </div>
        </div>
        <Button as="button" onClick={async () => await authorize(true)}>
          Confirm
        </Button>
        <Button as="button" onClick={async () => await authorize(false)}>
          Deny
        </Button>
      </div>
    );
  }
}
```
