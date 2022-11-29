defmodule CharonOauth2 do
  @moduledoc Mix.Project.config()[:description]

  @doc false
  def init_config(enum), do: __MODULE__.Config.from_enum(enum)
end
