defmodule CharonOauth2.Models.AuthorizationsTest do
  use CharonOauth2.DataCase
  alias MyApp.CharonOauth2.{Authorizations, Authorization}
  import MyApp.Seeds

  @config MyApp.CharonOauth2.Config.get()

  describe "all" do
    test "works" do
      assert [] == Authorizations.all()
    end
  end

  doctest Authorizations
end
