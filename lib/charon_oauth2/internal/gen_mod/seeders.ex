defmodule CharonOauth2.Internal.GenMod.Seeders do
  @moduledoc """

  """

  def generate(schemas_and_contexts, config) do
    alias CharonOauth2.Internal

    quote generated: true,
          location: :keep,
          bind_quoted: [schemas_and_contexts: schemas_and_contexts, config: config] do
      @mod_config Internal.get_module_config(config)
      @authorization_context schemas_and_contexts.authorizations
      @client_context schemas_and_contexts.clients
      @grant_context schemas_and_contexts.grants
      @repo @mod_config.repo
      @scopes @mod_config.scopes

      # @default_resource_owner %{} |> Map.put_new(@resource_owner_id_column, Ecto.UUID.generate())

      # defp insert_test_resource_owner!(resource_owner_id, overrides \\ []) do
      #   overrides
      #   |> Enum.into(@default_resource_owner)
      #   |> 
      # end

      @default_authorization %{
        scope: @scopes
      }

      def insert_test_authorization(resource_owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@default_authorization)
        |> Map.put_new(:resource_owner_id, resource_owner_id)
        |> Map.put_new_lazy(:client_id, fn -> insert_test_client!(resource_owner_id).id end)
        |> @authorization_context.insert()
      end

      def insert_test_authorization!(resource_owner_id, overrides \\ []) do
        insert_test_authorization(resource_owner_id, overrides)
        |> ok_or_raise("oauth2_authorization")
      end

      @default_client %{
        name: "MyClient",
        redirect_uris: ~w(https://mysite.tld),
        scope: @scopes,
        grant_types: "authorization_code",
        description: "MyDescription"
      }

      def insert_test_client(resource_owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@default_client)
        |> Map.put_new(:owner_id, resource_owner_id)
        |> @client_context.insert()
      end

      def insert_test_client!(resource_owner_id, overrides \\ []) do
        insert_test_client(resource_owner_id, overrides)
        |> ok_or_raise("oauth2_client")
      end

      @default_grant %{
        redirect_uri: "https://mysite.tld",
        type: "authorization_code"
      }

      def insert_test_grant(), do: raise("nuh uh")
      def insert_test_grant!(), do: raise("nuh uh")

      def insert_test_grant(resource_owner_id, overrides \\ []) do
        overrides
        |> Enum.into(@default_grant)
        |> Map.put_new_lazy(:authorization_id, fn ->
          insert_test_authorization!(resource_owner_id).id
        end)
        |> put_new_resource_owner(@authorization_context)
        |> @grant_context.insert()
      end

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
