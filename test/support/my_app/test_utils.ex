defmodule MyApp.TestUtils do
  @moduledoc false
  import ExUnit.Assertions
  import Charon.Utils

  def login(conn, _seeds = %{user: %{id: uid}}) do
    set_token_payload(conn, %{"sub" => uid})
  end

  def json_response(conn, status) do
    resp_body = conn.resp_body

    resp_body =
      case resp_body && Jason.decode(conn.resp_body) do
        nil -> nil
        {:ok, resp_body} -> resp_body
        {:error, _} -> resp_body
      end

    assert_status(conn, status, resp_body)
    assert resp_body not in [nil, ""], "no response body sent"
    resp_body
  end

  def assert_status(conn, status, decoded_body \\ nil) do
    assert conn.status == status,
      message:
        "expected status #{status} actual #{conn.status} with body #{inspect(decoded_body || conn.resp_body)}"

    conn
  end

  def get_resp_header(conn, header), do: conn.resp_headers |> Map.new() |> Map.get(header)
  def get_query_params(uri), do: uri |> Map.get(:query, "") |> URI.decode_query()

  def redir_response(conn, exp_redir_uri) do
    conn
    |> assert_status(302)
    |> get_resp_header("location")
    |> URI.new!()
    |> tap(&assert !exp_redir_uri || &1.host == exp_redir_uri |> URI.new!() |> Map.get(:host))
    |> get_query_params()
  end

  def assert_resp_headers(conn, exp) do
    resp_headers = conn.resp_headers |> Map.new()

    Enum.each(exp, fn {k, v} ->
      assert resp_headers[k] == v
    end)

    conn
  end

  def assert_dont_cache(conn) do
    assert_resp_headers(conn, %{"cache-control" => "no-store", "pragma" => "no-cache"})
  end
end
