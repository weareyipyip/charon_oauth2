defmodule CharonOauth2.Test.Repo do
  use Ecto.Repo,
    otp_app: :charon_oauth2,
    adapter: Ecto.Adapters.Postgres
end
