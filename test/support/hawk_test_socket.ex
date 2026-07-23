defmodule Hawk.TestSocket do
  @moduledoc """
  Builds a real `Phoenix.LiveView.Socket` for Hawk LiveView helper tests.

  Phoenix.Component.assign/3 tracks changed assigns through the socket's
  `__changed__` map, so a fresh socket must seed `assigns` with that key. Use
  `socket/0` for read-only assign helpers and `form_socket/0` when the test
  calls form helpers that build a `Phoenix.HTML.Form` through `to_form/2`.
  """

  def socket, do: %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

  def form_socket, do: socket()
end
