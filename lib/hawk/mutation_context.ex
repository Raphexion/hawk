defmodule Hawk.MutationContext do
  @moduledoc """
  Write-side state object shared by writer helpers and repository boundaries.

  A mutation context carries one model, incoming attributes, authority,
  validation state, policy-validation state, and metadata through a guarded
  writer pipeline.
  """

  alias Ecto.Changeset
  alias Hawk.Authority

  @type error :: :none | :invalid | :not_authorized

  @type t :: %__MODULE__{
          model: struct(),
          attrs: map(),
          authority: Authority.t(),
          changeset: Changeset.t(),
          error: error(),
          policy_validated?: boolean(),
          meta: map()
        }

  @enforce_keys [:model, :attrs, :authority, :changeset]
  defstruct [
    :model,
    :attrs,
    :authority,
    :changeset,
    error: :none,
    policy_validated?: false,
    meta: %{}
  ]

  @doc """
  Builds a fresh create context.
  """
  @spec create(struct(), map(), Authority.t()) :: t()
  def create(model, attrs, %Authority{} = authority) when is_struct(model) and is_map(attrs) do
    build(model, attrs, authority)
  end

  @doc """
  Builds a fresh update context.
  """
  @spec update(struct(), map(), Authority.t()) :: t()
  def update(model, attrs, %Authority{} = authority) when is_struct(model) and is_map(attrs) do
    build(model, attrs, authority)
  end

  @doc """
  Builds a fresh delete context.
  """
  @spec delete(struct(), Authority.t(), map()) :: t()
  def delete(model, %Authority{} = authority, attrs \\ %{})
      when is_struct(model) and is_map(attrs) do
    build(model, attrs, authority)
  end

  @doc """
  Adds a field validation error and marks the context invalid.
  """
  @spec add_error(t(), atom(), String.t(), keyword()) :: t()
  def add_error(%__MODULE__{} = context, field, message, opts \\ []) when is_atom(field) do
    %{
      context
      | changeset: Changeset.add_error(context.changeset, field, message, opts),
        error: :invalid
    }
  end

  @doc """
  Runs a function only while the context has no error.
  """
  @spec guard(t(), (t() -> t())) :: t()
  def guard(%__MODULE__{error: :none} = context, fun) when is_function(fun, 1) do
    fun.(context)
  end

  def guard(%__MODULE__{} = context, fun) when is_function(fun, 1), do: context

  @doc """
  Stores pipeline metadata.
  """
  @spec put_meta(t(), atom(), term()) :: t()
  def put_meta(%__MODULE__{meta: meta} = context, key, value) when is_atom(key) do
    %{context | meta: Map.put(meta, key, value)}
  end

  @doc """
  Evaluates write policy if the context is still valid.
  """
  @spec validate_policy(t(), (t() -> boolean())) :: t()
  def validate_policy(%__MODULE__{} = context, predicate) when is_function(predicate, 1) do
    guard(context, fn context ->
      if predicate.(context) do
        mark_policy_validated(context)
      else
        context
        |> mark_policy_validated()
        |> put_error(:not_authorized)
      end
    end)
  end

  @doc """
  Marks the context as having completed write-policy validation.
  """
  @spec mark_policy_validated(t()) :: t()
  def mark_policy_validated(%__MODULE__{} = context) do
    %{context | policy_validated?: true}
  end

  @doc """
  Sets the high-level context error.
  """
  @spec put_error(t(), error()) :: t()
  def put_error(%__MODULE__{} = context, error)
      when error in [:none, :invalid, :not_authorized] do
    %{context | error: error}
  end

  defp build(model, attrs, authority) do
    %__MODULE__{
      model: model,
      attrs: attrs,
      authority: authority,
      changeset: Changeset.change(model)
    }
  end
end
