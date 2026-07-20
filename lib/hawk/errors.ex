defmodule Hawk.Errors do
  @moduledoc """
  Converts Hawk writer results into API- and UI-friendly error shapes.
  """

  alias Ecto.Changeset
  alias Hawk.Error
  alias Hawk.MutationContext

  def to_json_api(error_or_result) do
    %{errors: Enum.map(to_errors(error_or_result), &json_api_error/1)}
  end

  def to_errors(%Error{} = error), do: [error]

  def to_errors({:not_authorized, %MutationContext{} = context}) do
    [Map.fetch!(context.meta, :authorization_error)]
  end

  def to_errors({:invalid, %MutationContext{} = context}) do
    Enum.map(context.changeset.errors, &validation_error/1)
  end

  def to_errors({:error, message}) when is_binary(message), do: [Error.error(message)]

  def to_live_view({:invalid, %MutationContext{} = context}) do
    {:error, changeset_errors(context.changeset)}
  end

  def to_live_view({:not_authorized, %MutationContext{} = context}) do
    error = Map.fetch!(context.meta, :authorization_error)
    {:error, %{base: [error.detail]}}
  end

  def to_live_view({:error, message}) when is_binary(message), do: {:error, %{base: [message]}}

  defp json_api_error(%Error{} = error) do
    %{
      status: to_string(error.status),
      code: to_string(error.code),
      title: error.title,
      detail: error.detail
    }
    |> put_optional(:source, error.source)
  end

  defp validation_error({field, {message, opts}}) do
    Error.invalid_attribute(field, interpolate(message, opts))
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

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
