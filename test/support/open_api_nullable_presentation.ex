defmodule Hawk.Test.OpenApiNullablePresentation do
  @moduledoc false
  use Hawk.JsonApi.Resource

  type("students")
  attribute(:deleted_at, nullable: true, doc: "Deletion timestamp.")
  attribute(:archived_at, source: :deleted_at, doc: "Archive timestamp.")

  def adapter(Videdal.Student), do: __MODULE__
  def adapter(_model), do: nil
end
