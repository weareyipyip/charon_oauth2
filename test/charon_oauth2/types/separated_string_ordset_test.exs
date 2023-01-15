defmodule CharonOauth2.Types.SeparatedStringOrdsetTest do
  use ExUnit.Case, async: true
  alias CharonOauth2.Types.SeparatedStringOrdset

  @opts SeparatedStringOrdset.init(pattern: ",")

  doctest SeparatedStringOrdset
end
