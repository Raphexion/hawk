defmodule Hawk.Schema do
  @moduledoc """
  Model introspection contract, decoupled from Ecto.

  `Hawk.Model` implements this by delegating to Ecto's `__schema__/1`.
  Non-Ecto models implement it directly, so Hawk's JSON:API adapter,
  document rendering, and validation work without a database.

  This is the "PreModel" seam: a model only needs to answer `:fields` and
  `:type` to back a flat JSON:API resource. `:associations` and `:association`
  are needed only when the model declares relationships.
  """

  @callback __hawk_schema__(:fields) :: [atom]
  @callback __hawk_schema__(:type, field :: atom) :: term | nil
  @callback __hawk_schema__(:associations) :: [atom]
  @callback __hawk_schema__(:association, name :: atom) :: term | nil
end
