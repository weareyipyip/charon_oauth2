defmodule MyApp.Repo.Migrations.AddCharonOauth2Models do
  use Ecto.Migration

  def change do
    create table("users") do
    end

    CharonOauth2.Migration.change("users", MyApp.CharonOauth2.Config.get())
  end
end
