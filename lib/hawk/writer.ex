defmodule Hawk.Writer do
  @moduledoc """
  Guarded writer helpers for mutation-context pipelines.

  These helpers are the runtime layer that future writer DSL declarations should
  compile into.
  """

  alias Ecto.Changeset
  alias Hawk.MutationContext

  @type validator_error ::
          {:error, atom(), String.t()}
          | {:error, atom(), String.t(), keyword()}

  @doc """
  Extracts a changeset from a mutation context for non-persisting form validation.

  The default `:validate` action follows Phoenix LiveView conventions: invalid
  changesets render errors while the form is being edited, without crossing the
  repository boundary.
  """
  @spec changeset(MutationContext.t(), atom()) :: Changeset.t()
  def changeset(%MutationContext{changeset: %Changeset{} = changeset}, action \\ :validate)
      when is_atom(action) do
    %{changeset | action: action}
  end

  @doc """
  Adds default attrs with put-if-missing semantics.

  Zero-arity function defaults are evaluated only when the default is applied.
  """
  @spec defaults(MutationContext.t(), map() | keyword()) :: MutationContext.t()
  def defaults(%MutationContext{} = context, defaults) do
    MutationContext.guard(context, fn context ->
      %{context | attrs: merge_defaults(context.attrs, Map.new(defaults))}
    end)
  end

  @doc """
  Casts permitted attrs into the context changeset.
  """
  @spec cast(MutationContext.t(), [atom()]) :: MutationContext.t()
  def cast(%MutationContext{} = context, permitted) when is_list(permitted) do
    MutationContext.guard(context, fn context ->
      context.changeset
      |> Changeset.cast(context.attrs, permitted)
      |> put_changeset(context)
    end)
  end

  @doc """
  Validates required fields on the context changeset.
  """
  @spec validate_required(MutationContext.t(), [atom()]) :: MutationContext.t()
  def validate_required(%MutationContext{} = context, fields) when is_list(fields) do
    validate_required(context, fields, [])
  end

  @doc """
  Validates required fields on the context changeset with Ecto options.
  """
  @spec validate_required(MutationContext.t(), [atom()], keyword()) :: MutationContext.t()
  def validate_required(%MutationContext{} = context, fields, opts)
      when is_list(fields) and is_list(opts) do
    MutationContext.guard(context, fn context ->
      context.changeset
      |> Changeset.validate_required(fields, opts)
      |> put_changeset(context)
    end)
  end

  @doc """
  Runs an Ecto changeset validator against the context changeset.

  Use this for validations that need native `Ecto.Changeset` APIs such as
  `validate_number/3`, `validate_inclusion/4`, or `unique_constraint/3`.
  Use `validate/2` for pure domain validators that return Hawk validator errors.
  """
  @spec validate_changeset(MutationContext.t(), (Changeset.t() -> Changeset.t())) ::
          MutationContext.t()
  def validate_changeset(
        %MutationContext{error: :none, changeset: %Changeset{valid?: false}} = context,
        validator
      )
      when is_function(validator, 1) do
    MutationContext.put_error(context, :invalid)
  end

  def validate_changeset(%MutationContext{} = context, validator)
      when is_function(validator, 1) do
    MutationContext.guard(context, fn context ->
      context.changeset
      |> validator.()
      |> put_changeset(context)
    end)
  end

  @doc """
  Normalizes changed string fields with the default string normalizer.
  """
  @spec normalize(MutationContext.t(), [atom()]) :: MutationContext.t()
  def normalize(%MutationContext{} = context, fields) do
    normalize(context, fields, &default_normalize/1)
  end

  @doc """
  Normalizes changed string fields with a custom unary function.
  """
  @spec normalize(MutationContext.t(), [atom()], (String.t() -> term())) :: MutationContext.t()
  def normalize(%MutationContext{} = context, fields, normalizer)
      when is_list(fields) and is_function(normalizer, 1) do
    MutationContext.guard(context, fn context ->
      changeset =
        Enum.reduce(fields, context.changeset, fn field, changeset ->
          normalize_change(changeset, field, normalizer)
        end)

      put_changeset(changeset, context)
    end)
  end

  @doc """
  Runs a custom validator against the mutation context.

  Supported return shapes:

    * `:ok`
    * `{:error, field, message}`
    * `{:error, field, message, opts}`
    * a list of either error tuple shape
  """
  @spec validate(MutationContext.t(), (MutationContext.t() ->
                                         :ok
                                         | validator_error()
                                         | [
                                             validator_error()
                                           ])) :: MutationContext.t()
  def validate(%MutationContext{} = context, validator) when is_function(validator, 1) do
    MutationContext.guard(context, fn context ->
      validator.(context)
      |> apply_validator_result(context)
    end)
  end

  defp resolve_default(value) when is_function(value, 0), do: value.()
  defp resolve_default(value), do: value

  defp merge_defaults(attrs, defaults) do
    Enum.reduce(defaults, attrs, fn {key, value}, acc ->
      put_default(acc, key, value)
    end)
  end

  defp put_default(attrs, key, _value) when is_map_key(attrs, key), do: attrs
  defp put_default(attrs, key, value), do: Map.put(attrs, key, resolve_default(value))

  defp normalize_change(changeset, field, normalizer) do
    case Changeset.fetch_change(changeset, field) do
      {:ok, value} when is_binary(value) ->
        Changeset.put_change(changeset, field, normalizer.(value))

      _other ->
        changeset
    end
  end

  defp default_normalize(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp apply_validator_result(:ok, context), do: context
  defp apply_validator_result([], context), do: context

  defp apply_validator_result([_head | _tail] = errors, context) do
    Enum.reduce(errors, context, &add_validator_error/2)
  end

  defp apply_validator_result(error, context) when is_tuple(error) do
    add_validator_error(error, context)
  end

  defp apply_validator_result(result, _context) do
    raise ArgumentError, "unsupported validator result: #{inspect(result)}"
  end

  defp add_validator_error({:error, field, message}, context)
       when is_atom(field) and is_binary(message) do
    MutationContext.add_error(context, field, message)
  end

  defp add_validator_error({:error, field, message, opts}, context)
       when is_atom(field) and is_binary(message) and is_list(opts) do
    MutationContext.add_error(context, field, message, opts)
  end

  defp add_validator_error(result, _context) do
    raise ArgumentError, "unsupported validator result: #{inspect(result)}"
  end

  defp put_changeset(%Changeset{} = changeset, %MutationContext{} = context) do
    context = %{context | changeset: changeset}

    if changeset.valid? do
      context
    else
      MutationContext.put_error(context, :invalid)
    end
  end
end
