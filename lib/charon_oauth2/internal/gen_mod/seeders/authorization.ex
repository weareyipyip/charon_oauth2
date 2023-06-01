defmodule CharonOauth2.Seeders.Authorization do
  @moduledoc """

  """

  def generate(
        %{authorization: _authorization_schema, authorizations: authorization_context} = _schemas,
        %{scopes: scopes} = _module_config,
        repo
      ) do
    quote do
      @authorization_context unquote(authorization_context)
      @repo unquote(repo)

      @default_authorization %{
        scope: scopes
      }

      def insert_test_authorization(overrides) do
        overrides
        |> Map.merge(@default_authorization)
        |> @authorization_context.insert()
      end
    end
  end
end
