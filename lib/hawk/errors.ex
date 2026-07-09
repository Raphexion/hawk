defmodule Hawk.Errors do
  @moduledoc """
  Converts Hawk writer results into API- and UI-friendly error shapes.
  """

  alias Ecto.Changeset
  alias Hawk.MutationContext

  def to_json_api({:not_authorized, %MutationContext{} = context}) do
    error = Map.fetch!(context.meta, :authorization_error)

    %{
      errors: [
        %{
          status: "403",
          code: to_string(error.code),
          title: error.title,
          detail: error.detail
        }
      ]
    }
  end

  def to_json_api({:invalid, %MutationContext{} = context}) do
    %{errors: Enum.map(context.changeset.errors, &validation_error/1)}
  end

  def to_json_api({:error, message}) when is_binary(message) do
    %{errors: [%{status: "500", code: "error", title: "Error", detail: message}]}
  end

  def to_live_view({:invalid, %MutationContext{} = context}) do
    {:error, changeset_errors(context.changeset)}
  end

  def to_live_view({:not_authorized, %MutationContext{} = context}) do
    error = Map.fetch!(context.meta, :authorization_error)
    {:error, %{base: [error.detail]}}
  end

  def to_live_view({:error, message}) when is_binary(message), do: {:error, %{base: [message]}}

  defp validation_error({field, {message, opts}}) do
    %{
      status: "422",
      code: "invalid",
      title: "Invalid attribute",
      detail: interpolate(message, opts),
      source: %{pointer: "/data/attributes/#{field}"}
    }
  end

  defp changeset_errors(%Changeset{} = changeset) do
    Map.new(changeset.errors, fn {field, {message, opts}} ->
      {field, [interpolate(message, opts)]}
    end)
  end

  defp interpolate(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", stringify_interpolation(value))
    end)
  end

  defp stringify_interpolation(value) do
    to_string(value)
  rescue
    Protocol.UndefinedError -> inspect(value)
  end
end
