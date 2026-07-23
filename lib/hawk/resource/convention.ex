defmodule Hawk.Resource.Convention do
  @moduledoc """
  Infers sibling resource modules from a model by naming convention.

  Hawk resources follow a convention: `MyApp.Course` (model) is backed by
  `MyApp.Courses` (resource facade), `MyApp.Courses.Reader`, and
  `MyApp.Courses.Policy`. This module owns that inference so it is a single,
  discoverable, testable concept rather than buried in `Hawk.Model` macro
  internals.

  Convention is the default; models can override it per-association with the
  `:resource`, `:policy`, or `:reader` opts on `belongs_to`/`has_many`/
  `many_to_many` inside a `model do` block.
  """

  @doc """
  Infers the resource facade module for a model by pluralizing its last segment.

      Convention.resource_module(MyApp.Course)  #=> MyApp.Courses

  When the last namespace segment already matches the pluralized name, the
  namespace is returned as-is (so `MyApp.Courses` stays `MyApp.Courses`).
  """
  def resource_module(module) when is_atom(module) do
    parts = Module.split(module)
    resource = parts |> List.last() |> pluralize()
    namespace = Enum.drop(parts, -1)

    if List.last(namespace) == resource do
      Module.concat(namespace)
    else
      namespace
      |> Kernel.++([resource])
      |> Module.concat()
    end
  end

  @doc """
  Infers the sibling policy module for a model.

      Convention.policy_module(MyApp.Course)  #=> MyApp.Courses.Policy
  """
  def policy_module(module) when is_atom(module) do
    Module.concat(resource_module(module), Policy)
  end

  @doc """
  Infers the sibling reader module for a model.

      Convention.reader_module(MyApp.Course)  #=> MyApp.Courses.Reader
  """
  def reader_module(module) when is_atom(module) do
    Module.concat(resource_module(module), Reader)
  end

  @doc """
  Pluralizes a singular resource name following common English rules.

  Handles `y → ies` (consonant + y), `sis → ses`, and `s/x/z/ch/sh → +es`.
  Falls back to `+s` for everything else.

  Note: irregular plurals (`child → children`, `person → people`) are not
  handled; models with those names should pass an explicit `:resource` opt on
  their associations.
  """
  def pluralize(name) when is_binary(name) do
    cond do
      String.ends_with?(name, "sis") ->
        String.replace_suffix(name, "sis", "ses")

      String.ends_with?(name, "y") and not vowel_before?(name, "y") ->
        String.replace_suffix(name, "y", "ies")

      Regex.match?(~r/(s|x|z|ch|sh)$/, name) ->
        name <> "es"

      true ->
        name <> "s"
    end
  end

  defp vowel_before?(name, suffix) do
    base = String.replace_suffix(name, suffix, "")

    case String.last(base) do
      nil -> false
      char -> char in ["a", "e", "i", "o", "u"]
    end
  end
end
