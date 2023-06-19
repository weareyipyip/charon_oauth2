defmodule CharonOauth2.Models.AuthorizationsTest do
  use CharonOauth2.DataCase
  alias MyApp.CharonOauth2.{Authorizations, Authorization}
  import MyApp.CharonOauth2.TestSeeds

  describe "all" do
    test "works" do
      assert [] == Authorizations.all()
    end

    test "all bindings resolvable" do
      assert %Ecto.Query{} =
               Enum.reduce(
                 Authorization.supported_preloads(),
                 Authorization.named_binding(),
                 &Authorization.resolve_binding(&2, &1)
               )
    end
  end

  doctest Authorizations
end
