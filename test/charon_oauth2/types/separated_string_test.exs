defmodule CharonOauth2.Types.SeparatedStringTest do
  use ExUnit.Case, async: true
  alias CharonOauth2.Types.SeparatedString

  @opts SeparatedString.init(pattern: ",")

  doctest SeparatedString
end
