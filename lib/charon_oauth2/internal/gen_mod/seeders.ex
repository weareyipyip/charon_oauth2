defmodule CharonOauth2.Internal.GenMod.Seeders do
  @moduledoc false

  def generate(schemas_and_contexts, config) do
    alias CharonOauth2.Internal
    alias Ecto.Changeset

    quote generated: true,
          location: :keep,
          bind_quoted: [schemas_and_contexts: schemas_and_contexts, config: config] do
      @moduledoc """
      Helper module to aid in writing seeders. Uses default values described below.

      All default values mentioned can be configured within `CharonOauth2.Config` at `:seeder_overrides`,
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
      @default_overrides @mod_config.seeder_overrides

      @base_default_authorization %{scope: ~w(my_scope)}
      @default_authorization Map.get(@default_overrides, :authorization, %{})
                             |> Enum.into(@base_default_authorization)

      @doc """
      Inserts an authorization using `#{inspect(@authorization_context)}.insert/1`.

      Default value's fields can be overwritten using `overrides`.

      ```
      #{inspect(@base_default_authorization, pretty: true)}
      ```
      """
      @spec insert_test_authorization(integer(), keyword()) ::
              {:ok, @authorization_schema.t()} | {:error, Changeset.t()}
      def insert_test_authorization(resource_owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@default_authorization)
        |> Map.put_new(:resource_owner_id, resource_owner_id)
        |> Map.put_new_lazy(:client_id, fn -> insert_test_client!(resource_owner_id).id end)
        |> @authorization_context.insert()
      end

      @doc """
      Inserts an authorization using `#{inspect(@authorization_context)}.insert/1`. Raises on failure.

      Default value's fields can be overwritten using `overrides`.

      ```
      #{inspect(@base_default_authorization, pretty: true)}
      ```
      """
      @spec insert_test_authorization!(integer(), keyword()) :: @authorization_schema.t()
      def insert_test_authorization!(resource_owner_id, overrides \\ []) do
        insert_test_authorization(resource_owner_id, overrides)
        |> ok_or_raise("oauth2_authorization")
      end

      @base_default_client %{
        name: "MyClient",
        redirect_uris: ~w(https://mysite.tld),
        scope: ~w(my_scope my_other_scope),
        grant_types: ~w(my_grant_type),
        description: "MyDescription"
      }
      @default_client Map.get(@default_overrides, :client, %{}) |> Enum.into(@base_default_client)

      @doc """
      Inserts a client using `#{inspect(@client_context)}.insert/1`.

      Default value's fields can be overwritten using `overrides`.

      ```
      #{inspect(@base_default_client, pretty: true)}
      ```
      """
      @spec insert_test_client(integer(), keyword()) ::
              {:ok, @client_schema.t()} | {:error, Changeset.t()}
      def insert_test_client(resource_owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@default_client)
        |> Map.put_new(:owner_id, resource_owner_id)
        |> @client_context.insert()
      end

      @doc """
      Inserts a client using `#{inspect(@client_context)}.insert/1`. Raises on failure.

      Default value's fields can be overwritten using `overrides`.

      ```
      #{inspect(@base_default_client, pretty: true)}
      ```
      """
      @spec insert_test_client!(integer(), keyword()) :: @client_schema.t()
      def insert_test_client!(resource_owner_id, overrides \\ []) do
        insert_test_client(resource_owner_id, overrides)
        |> ok_or_raise("oauth2_client")
      end

      @base_default_grant %{
        redirect_uri: "https://mysite.tld",
        type: "my_grant_type"
      }
      @default_grant Map.get(@default_overrides, :grant, %{})
                     |> Enum.into(@base_default_grant)

      @doc """
      Inserts a grant using `#{inspect(@grant_context)}.insert/1`.

      Default value's fields can be overwritten using `overrides`.

      ```
      #{inspect(@base_default_grant, pretty: true)}
      ```
      """
      @spec insert_test_grant(integer(), keyword()) ::
              {:ok, @grant_schema.t()} | {:error, Changeset.t()}
      def insert_test_grant(resource_owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@default_grant)
        |> Map.put_new_lazy(:authorization_id, fn ->
          insert_test_authorization!(resource_owner_id).id
        end)
        |> put_new_resource_owner(@authorization_context)
        |> @grant_context.insert()
      end

      @doc """
      Inserts a grant using `#{inspect(@grant_context)}.insert/1`. Raises on failure.

      Default value's fields can be overwritten using `overrides`.

      ```
      #{inspect(@base_default_grant, pretty: true)}
      ```
      """
      @spec insert_test_grant!(integer(), keyword()) :: @grant_schema.t()
      def insert_test_grant!(resource_owner_id, overrides \\ []) do
        insert_test_grant(resource_owner_id, overrides)
        |> ok_or_raise("oauth2_grant")
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
