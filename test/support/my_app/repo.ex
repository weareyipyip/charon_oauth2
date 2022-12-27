defmodule MyApp.Repo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :charon_oauth2,
    adapter: Ecto.Adapters.Postgres
end
