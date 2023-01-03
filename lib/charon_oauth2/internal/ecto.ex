defmodule CharonOauth2.Internal.Ecto do
  @moduledoc false

  defmacro set_contains_any(field, value) do
    quote do
      fragment("? && ?", unquote(field), ^unquote(value))
    end
  end
end
