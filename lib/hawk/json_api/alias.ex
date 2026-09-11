defmodule Hawk.JsonApi.Alias do
  @moduledoc """
  Declarative alternate JSON:API presentation for an existing Hawk resource.

  Aliases contain presentation metadata only. Reads, writes, policies, and
  actions continue to run through the referenced canonical resource.
  """

  defmacro __using__(opts) do
    resource = Keyword.fetch!(opts, :resource)
    alias_key = Keyword.fetch!(opts, :alias)

    quote do
      use Hawk.JsonApi.Resource
      @hawk_alias_resource unquote(resource)
      @hawk_alias_key unquote(alias_key)

      @doc false
      def __hawk_alias__,
        do: %{resource: @hawk_alias_resource, key: @hawk_alias_key, adapter: __MODULE__}
    end
  end
end
