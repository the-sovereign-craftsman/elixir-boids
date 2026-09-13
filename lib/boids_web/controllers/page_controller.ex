defmodule BoidsWeb.PageController do
  use BoidsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
