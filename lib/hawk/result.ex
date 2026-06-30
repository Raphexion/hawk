defmodule Hawk.Result do
  @moduledoc """
  Helpers for converting mutation contexts into public writer result tuples.
  """

  alias Hawk.MutationContext

  @type t(model) ::
          {:ok, model}
          | :ok
          | {:invalid, MutationContext.t()}
          | {:not_authorized, MutationContext.t()}
          | {:error, String.t()}

  @doc """
  Converts a mutation context and success value into the standard result shape.
  """
  @spec from_context(MutationContext.t(), model) :: t(model) when model: term()
  def from_context(%MutationContext{error: :none}, model), do: {:ok, model}

  def from_context(%MutationContext{error: :invalid} = context, _model) do
    {:invalid, context}
  end

  def from_context(%MutationContext{error: :not_authorized} = context, _model) do
    {:not_authorized, context}
  end

  @doc """
  Returns a framework-level error result for failures that are not field errors.
  """
  @spec error(String.t()) :: {:error, String.t()}
  def error(message) when is_binary(message), do: {:error, message}
end
