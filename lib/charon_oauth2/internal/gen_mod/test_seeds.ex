defmodule CharonOauth2.Internal.GenMod.TestSeeds do
  @moduledoc false

  def generate(schemas_and_contexts, config) do
    alias CharonOauth2.Internal
    alias Ecto.Changeset

    quote generated: true,
          location: :keep,
          bind_quoted: [schemas_and_contexts: schemas_and_contexts, config: config] do
      @moduledoc """
      Insert test values for writing tests. Uses default values described below.

      All functions take an `overrides` parameter that can be used to override the default values.
      In order to set your own defaults, you can use the `CharonOauth2.Config` field `:test_seed_defaults`.
      """

      @mod_config Internal.get_module_config(config)
      @authorization_context schemas_and_contexts.authorizations
      @client_context schemas_and_contexts.clients
      @grant_context schemas_and_contexts.grants

      @authorization_schema schemas_and_contexts.authorization
      @client_schema schemas_and_contexts.client
      @grant_schema schemas_and_contexts.grant

      @repo @mod_config.repo
      @scopes @mod_config.scopes
      @default_overrides @mod_config.test_seed_defaults

      @client_defaults Enum.into(
                         @default_overrides[:client] || [],
                         %{
                           name: "MyClient",
                           redirect_uris: ~w(https://mysite.tld),
                           scope: @scopes,
                           grant_types: ~w(authorization_code),
                           description:
                             "Incredibly innovative application that definitely treats your data well."
                         }
                       )

      @doc """
      Inserts a client using `#{@client_context}.insert/1`.

      The default values can be overridden using `overrides`. These are the default values:

      ```
      #{inspect(@client_defaults, pretty: true)}
      ```
      """
      @spec insert_test_client(any(), keyword()) ::
              {:ok, @client_schema.t()} | {:error, Changeset.t()}
      def insert_test_client(owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@client_defaults)
        |> Map.put_new(:owner_id, owner_id)
        |> @client_context.insert()
      end

      @doc """
      Inserts a client using `#{@client_context}.insert/1`. Raises on failure.

      The default values can be overridden using `overrides`. These are the default values:

      ```
      #{inspect(@client_defaults, pretty: true)}
      ```
      """
      @spec insert_test_client!(any(), keyword()) :: @client_schema.t()
      def insert_test_client!(owner_id, overrides \\ []) do
        insert_test_client(owner_id, overrides) |> ok_or_raise("oauth2_client")
      end

      @authorization_defaults Enum.into(
                                @default_overrides[:authorization] || [],
                                %{scope: @scopes}
                              )

      @doc """
      Inserts an authorization using `#{@authorization_context}.insert/1`.

      The default values can be overridden using `overrides`. These are the default values:

      ```
      #{inspect(@authorization_defaults, pretty: true)}
      ```
      """
      @spec insert_test_authorization(any(), keyword()) ::
              {:ok, @authorization_schema.t()} | {:error, Changeset.t()}
      def insert_test_authorization(resource_owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@authorization_defaults)
        |> Map.put_new(:resource_owner_id, resource_owner_id)
        |> Map.put_new_lazy(:client_id, fn -> insert_test_client!(resource_owner_id).id end)
        |> @authorization_context.insert()
      end

      @doc """
      Inserts an authorization using `#{@authorization_context}.insert/1`. Raises on failure.

      The default values can be overridden using `overrides`. These are the default values:

      ```
      #{inspect(@authorization_defaults, pretty: true)}
      ```
      """
      @spec insert_test_authorization!(any(), keyword()) :: @authorization_schema.t()
      def insert_test_authorization!(resource_owner_id, overrides \\ []) do
        insert_test_authorization(resource_owner_id, overrides)
        |> ok_or_raise("oauth2_authorization")
      end

      @grant_defaults Enum.into(@default_overrides[:grant] || [], %{
                        redirect_uri: "https://mysite.tld",
                        type: "authorization_code"
                      })

      @doc """
      Inserts a grant using `#{@grant_context}.insert/1`.

      The default values can be overridden using `overrides`. These are the default values:

      ```
      #{inspect(@grant_defaults, pretty: true)}
      ```
      """
      @spec insert_test_grant(any(), keyword()) ::
              {:ok, @grant_schema.t()} | {:error, Changeset.t()}
      def insert_test_grant(resource_owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@grant_defaults)
        |> Map.put_new_lazy(:authorization_id, fn ->
          insert_test_authorization!(resource_owner_id).id
        end)
        |> put_new_resource_owner(@authorization_context)
        |> @grant_context.insert()
      end

      @doc """
      Inserts a grant using `#{@grant_context}.insert/1`. Raises on failure.

      The default values can be overridden using `overrides`. These are the default values:

      ```
      #{inspect(@grant_defaults, pretty: true)}
      ```
      """
      @spec insert_test_grant!(any(), keyword()) :: @grant_schema.t()
      def insert_test_grant!(resource_owner_id, overrides \\ []) do
        insert_test_grant(resource_owner_id, overrides) |> ok_or_raise("oauth2_grant")
      end

      ###########
      # PRIVATE #
      ###########

      defp put_new_resource_owner(%{resource_owner_id: _} = grant, _auth_context), do: grant

      defp put_new_resource_owner(%{authorization_id: auth_id} = grant, auth_context) do
        owner_id =
          if auth = auth_context.get_by(id: auth_id) do
            auth.resource_owner_id
          else
            -1
          end

        Map.put(grant, :resource_owner_id, owner_id)
      end

      defp put_new_resource_owner(_, _),
        do: raise("Grant must contain either :resource_owner_id or :authorization_id")

      defp ok_or_raise({:ok, entity}, _entity_name), do: entity

      defp ok_or_raise({:error, %Ecto.Changeset{} = cs}, entity_name),
        do: raise("#{entity_name} insertion failed: #{inspect(cs, pretty: true)}")
    end
  end
end
