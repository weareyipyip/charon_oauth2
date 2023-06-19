defmodule CharonOauth2.Models.GrantsTest do
  use CharonOauth2.DataCase
  alias MyApp.CharonOauth2.{Grants, Grant}
  import MyApp.CharonOauth2.Seeders

  test "all bindings resolvable" do
    assert %Ecto.Query{} =
             Enum.reduce(
               Grant.supported_preloads(),
               Grant.named_binding(),
               &Grant.resolve_binding(&2, &1)
             )
  end

  doctest Grants
end
