defmodule CharonOauth2.Internal.Plug do
  @moduledoc false
  import Plug.Conn

  def redirect(conn, to) do
    conn
    |> put_resp_content_type("application/json")
    |> dont_cache()
    |> send_resp(200, Jason.encode!(%{redirect_to: to}))
  end

  def dont_cache(conn) do
    conn |> put_resp_header("cache-control", "no-store") |> put_resp_header("pragma", "no-cache")
  end

  def redirect_with_query(conn, to, query_params) do
    query_params = query_params |> URI.encode_query()
    to = to |> URI.new!() |> append_query(query_params) |> URI.to_string()
    redirect(conn, to)
  end

  def error_redirect(conn, cs, error, descr) do
    changes = cs.changes
    uri = changes.resolved_redir_uri
    state = changes[:state]
    error_redirect(conn, uri, error, descr, state)
  end

  def error_redirect(conn, to, error, descr, state) do
    query = %{error: error, error_description: descr} |> put_non_nil(:state, state)
    redirect_with_query(conn, to, query)
  end

  def json(conn, status, data, %{config: %{json_module: jmod}}) do
    conn
    |> put_resp_content_type("application/json")
    |> dont_cache()
    |> send_resp(status, jmod.encode!(data))
  end

  def json_error(conn, status, error, descr, opts) do
    json(conn, status, %{error: error, error_description: descr}, opts)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      {:error, changeset} = Accounts.create_user(%{password: "short"})
      "password is too short" in changeset_errors_to_map(changeset).password
      %{password: ["password is too short"]} = changeset_errors_to_map(changeset)
  """
  @spec changeset_errors_to_map({:error, Ecto.Changeset.t()} | Ecto.Changeset.t()) :: map
  def changeset_errors_to_map(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  def changeset_errors_to_map({:error, changeset}), do: changeset_errors_to_map(changeset)
  def changeset_errors_to_map(other), do: other

  def cs_error_map_to_string(cs) do
    cs
    |> Stream.flat_map(fn {k, values} -> Enum.map(values, &"#{k}: #{&1}") end)
    |> Enum.join(", ")
  end

  def put_non_nil(map, _key, _value = nil), do: map
  def put_non_nil(map, key, value), do: Map.put(map, key, value)

  # nicked from Elixir 1.14, to support 1.13
  defp append_query(%URI{} = uri, query) when uri.query in [nil, ""] do
    %{uri | query: query}
  end

  defp append_query(%URI{} = uri, query) do
    if String.ends_with?(uri.query, "&") do
      %{uri | query: uri.query <> query}
    else
      %{uri | query: uri.query <> "&" <> query}
    end
  end
end
