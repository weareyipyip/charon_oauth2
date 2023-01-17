defmodule CharonOauth2.Internal.Plug do
  @moduledoc false
  alias Plug.Conn
  alias Ecto.Changeset
  import Conn

  @doc """
  Send a "redirect response", that is, a 200 OK response with JSON
  with a `redirect_to` value.
  """
  @spec redirect(Conn.t(), String.t()) :: Conn.t()
  def redirect(conn, to) do
    conn
    |> put_resp_content_type("application/json")
    |> dont_cache()
    |> send_resp(200, Jason.encode!(%{redirect_to: to}))
  end

  @doc """
  Instruct the user agent and proxies in between not to cache the response.
  """
  @spec dont_cache(Conn.t()) :: Conn.t()
  def dont_cache(conn) do
    # https://datatracker.ietf.org/doc/html/rfc6749#section-5.1
    conn |> put_resp_header("cache-control", "no-store") |> put_resp_header("pragma", "no-cache")
  end

  @doc """
  Append `query_params` to `to` and then send a redirect response.
  """
  @spec redirect_with_query(Conn.t(), binary | URI.t(), Enumerable.t()) :: Conn.t()
  def redirect_with_query(conn, to, query_params) do
    query_params = query_params |> URI.encode_query()
    to = to |> URI.new!() |> append_query(query_params) |> URI.to_string()
    redirect(conn, to)
  end

  @doc """
  Send a "redirect error", instructing the user agent to redirect to the client.
  The redirect URI is grabbed from the changeset.
  """
  @spec error_redirect(Conn.t(), Changeset.t(), binary, binary) :: Conn.t()
  def error_redirect(conn, cs, error, descr) do
    changes = cs.changes
    uri = changes.resolved_redir_uri
    state = changes[:state]
    error_redirect(conn, uri, error, descr, state)
  end

  @doc """
  Send a "redirect error", instructing the user agent to redirect to the client.
  """
  @spec error_redirect(Conn.t(), binary | URI.t(), String.t(), String.t(), String.t() | nil) ::
          Conn.t()
  def error_redirect(conn, to, error, descr, state) do
    query = %{error: error, error_description: descr} |> put_non_nil(:state, state)
    redirect_with_query(conn, to, query)
  end

  @doc """
  Send a JSON response with `status`.
  """
  @spec json(Conn.t(), pos_integer(), any, %{config: Charon.Config.t()}) :: Conn.t()
  def json(conn, status, data, %{config: %{json_module: jmod}}) do
    conn
    |> put_resp_content_type("application/json")
    |> dont_cache()
    |> send_resp(status, jmod.encode!(data))
  end

  @doc """
  Send an error as a JSON response.
  """
  @spec json_error(Conn.t(), pos_integer(), String.t(), String.t(), %{config: Charon.Config.t()}) ::
          Conn.t()
  def json_error(conn, status, error, descr, opts) do
    json(conn, status, %{error: error, error_description: descr}, opts)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      {:error, changeset} = Accounts.create_user(%{password: "short"})
      "password is too short" in changeset_errors_to_map(changeset).password
      %{password: ["password is too short"]} = changeset_errors_to_map(changeset)
  """
  @spec changeset_errors_to_map({:error, Changeset.t()} | Changeset.t()) :: map
  def changeset_errors_to_map(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {message, _opts} ->
      message
      # IO.inspect({message, opts})
      # Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      #   opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      # end)
    end)
  end

  def changeset_errors_to_map({:error, changeset}), do: changeset_errors_to_map(changeset)

  @doc """
  Create a single error message out of the error map of a changeset (from `changeset_errors_to_map/1`).
  """
  @spec cs_error_map_to_string(map) :: binary
  def cs_error_map_to_string(map) do
    map
    |> Stream.flat_map(fn {k, values} -> Enum.map(values, &"#{k}: #{&1}") end)
    |> Enum.join(", ")
  end

  @doc """
  Put {key, value} in map if value is not nil.
  """
  @spec put_non_nil(map, any, any) :: map
  def put_non_nil(map, _key, _value = nil), do: map
  def put_non_nil(map, key, value), do: Map.put(map, key, value)

  ###########
  # Private #
  ###########

  # nicked from Elixir 1.14, so that we can support 1.13
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
