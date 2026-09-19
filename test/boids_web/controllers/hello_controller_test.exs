defmodule BoidsWeb.HelloControllerTest do
  use BoidsWeb.ConnCase

  test "GET /hello", %{conn: conn} do
    conn = get(conn, ~p"/hello")
    assert html_response(conn, 200) =~ "Hello World, from Phoenix!"
  end
end
