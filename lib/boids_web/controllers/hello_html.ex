defmodule BoidsWeb.HelloHTML do
  use BoidsWeb, :html

  embed_templates "hello_html/*"

  attr :messenger, :string, required: true

  def greet(assigns) do
    ~H"""
    <h2>Hello World, from {@messenger}!</h2>
    """
  end
end
