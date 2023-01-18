defmodule CharonOauth2.Types.SeparatedStringMapSetTest do
  use ExUnit.Case, async: true
  alias CharonOauth2.Types.SeparatedStringMapSet

  @opts SeparatedStringMapSet.init(pattern: ",")

  doctest SeparatedStringMapSet
end
