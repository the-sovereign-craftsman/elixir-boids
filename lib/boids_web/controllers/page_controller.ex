defmodule BoidsWeb.PageController do
  use BoidsWeb, :controller

  def home(conn, _params) do
    conn
    |> put_flash(:error, "Lets pretend we have an error")
    |> redirect(to: ~p"/redirect_test")
  end

  def redirect_test(conn, _params) do
    render(conn, :home)
  end
end
