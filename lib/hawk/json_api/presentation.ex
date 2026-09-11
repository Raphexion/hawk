defmodule Hawk.JsonApi.Presentation do
  @moduledoc "Behaviour for a complete JSON:API vocabulary/profile."

  @callback adapter(module()) :: module() | nil

  def adapter(presentation, model) when is_atom(presentation) and is_atom(model) do
    if Code.ensure_loaded?(presentation) and function_exported?(presentation, :adapter, 1),
      do: presentation.adapter(model)
  end

  def adapter(_presentation, _model), do: nil
end
