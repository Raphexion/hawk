defmodule Hawk.Error do
  @moduledoc """
  Canonical structured Hawk error.

  Resource internals carry this shape and adapters render it into their own
  response formats, for example JSON:API error objects or LiveView assigns.
  """

  @enforce_keys [:status, :code, :title, :detail]
  defstruct [:status, :code, :title, :detail, :source]

  @type t :: %__MODULE__{
          status: pos_integer(),
          code: atom(),
          title: String.t(),
          detail: String.t(),
          source: map() | nil
        }

  @doc """
  Builds a `400 Bad request` error.
  """
  @spec bad_request(String.t()) :: t()
  def bad_request(detail) when is_binary(detail) do
    %__MODULE__{status: 400, code: :bad_request, title: "Bad request", detail: detail}
  end

  @doc """
  Builds a `403 Not authorized` error.
  """
  @spec not_authorized(String.t()) :: t()
  def not_authorized(detail) when is_binary(detail) do
    %__MODULE__{status: 403, code: :not_authorized, title: "Not authorized", detail: detail}
  end

  @doc """
  Builds a `422 Invalid attribute` error for a JSON:API attribute pointer.
  """
  @spec invalid_attribute(atom(), String.t()) :: t()
  def invalid_attribute(field, detail) when is_atom(field) and is_binary(detail) do
    %__MODULE__{
      status: 422,
      code: :invalid,
      title: "Invalid attribute",
      detail: detail,
      source: %{pointer: "/data/attributes/#{field}"}
    }
  end

  @doc """
  Builds a generic `500 Error`.
  """
  @spec error(String.t()) :: t()
  def error(detail) when is_binary(detail) do
    %__MODULE__{status: 500, code: :error, title: "Error", detail: detail}
  end
end
