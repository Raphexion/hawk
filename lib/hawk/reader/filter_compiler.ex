defmodule Hawk.Reader.FilterCompiler do
  @moduledoc """
  Compiles Hawk filter ASTs into Ecto query predicates.

  This module implements the default direct-field behavior. Direct integer
  filters are cast and operator-checked before query construction so malformed
  external input fails as `ArgumentError` instead of escaping from Ecto later.
  Declared coordinate filters dispatch through `Hawk.Reader.Coordinates` before
  generic custom handlers. Reader modules layer custom handlers and join
  planning around this compiler.
  """

  import Ecto.Query

  alias Hawk.Filter

  @operators [:eq, :neq, :in, :not_in, :lt, :lte, :gt, :gte, :like, :ilike, :near]
  @integer_operators [:eq, :neq, :in, :not_in, :lt, :lte, :gt, :gte]
  @comparison_operators [:lt, :lte, :gt, :gte]

  @type handler :: (Filter.value() -> Ecto.Query.dynamic_expr() | :all | :none)
  @type handlers :: %{optional(atom()) => handler()}
  @type coordinate_filters :: %{optional(atom()) => Hawk.Reader.Coordinates.options()}

  @doc """
  Applies a filter AST to an Ecto queryable.

  `schema` is used to validate direct fields. Unknown fields fail loudly unless
  a custom handler exists for the key.
  """
  @spec compile(Ecto.Queryable.t(), module(), Filter.t(), handlers(), coordinate_filters()) ::
          Ecto.Query.t()
  def compile(queryable, schema, filter, handlers \\ %{}, coordinate_filters \\ %{})
      when is_atom(schema) do
    reject_unsupported_operator_shorthand!(filter, handlers)
    query = Ecto.Queryable.to_query(queryable)

    case compile_filter(schema, Filter.normalize(filter), handlers, coordinate_filters) do
      :all -> query
      :none -> where(query, false)
      dynamic -> where(query, ^dynamic)
    end
  end

  defp compile_filter(_schema, :all, _handlers, _coordinate_filters), do: :all
  defp compile_filter(_schema, :none, _handlers, _coordinate_filters), do: :none

  defp compile_filter(schema, {:and, left, right}, handlers, coordinate_filters) do
    combine(
      :and,
      compile_filter(schema, left, handlers, coordinate_filters),
      compile_filter(schema, right, handlers, coordinate_filters)
    )
  end

  defp compile_filter(schema, {:or, left, right}, handlers, coordinate_filters) do
    combine(
      :or,
      compile_filter(schema, left, handlers, coordinate_filters),
      compile_filter(schema, right, handlers, coordinate_filters)
    )
  end

  defp compile_filter(schema, filter, handlers, coordinate_filters) when is_map(filter) do
    Enum.reduce(filter, :all, fn {field, value}, acc ->
      combine(:and, acc, compile_value(schema, field, value, handlers, coordinate_filters))
    end)
  end

  defp compile_value(schema, field, value, handlers, coordinate_filters) do
    case Map.fetch(coordinate_filters, field) do
      {:ok, metadata} ->
        Hawk.Reader.Coordinates.filter_dynamic(field, value, metadata)

      :error ->
        reject_undeclared_near!(field, value)

        case Map.fetch(handlers, field) do
          {:ok, handler} -> run_handler!(field, handler, value)
          :error -> compile_root_field_value(schema, field, value)
        end
    end
  end

  defp reject_undeclared_near!(field, {:near, _params}) do
    raise ArgumentError,
          "filter operator :near requires a declared coordinate filter for field #{inspect(field)}"
  end

  defp reject_undeclared_near!(_field, _value), do: :ok

  defp run_handler!(field, handler, value) when is_function(handler, 1) do
    case handler.(value) do
      %Ecto.Query.DynamicExpr{} = dynamic ->
        dynamic

      :all ->
        :all

      :none ->
        :none

      unsupported ->
        raise ArgumentError,
              "filter handler #{inspect(field)} returned unsupported value #{inspect(unsupported)}"
    end
  end

  defp compile_root_field_value(schema, field, value) do
    validate_field!(schema, field)

    value = prepare_root_field_value!(schema, field, value)
    compile_validated_root_field_value(field, value)
  end

  defp compile_validated_root_field_value(field, {:eq, nil}) do
    dynamic([row], is_nil(field(row, ^field)))
  end

  defp compile_validated_root_field_value(field, {:neq, nil}) do
    dynamic([row], not is_nil(field(row, ^field)))
  end

  defp compile_validated_root_field_value(field, {:eq, value}) do
    dynamic([row], field(row, ^field) == ^value)
  end

  defp compile_validated_root_field_value(field, {:neq, value}) do
    dynamic([row], field(row, ^field) != ^value)
  end

  defp compile_validated_root_field_value(_field, {:in, []}), do: :none

  defp compile_validated_root_field_value(field, {:in, values}) when is_list(values) do
    dynamic([row], field(row, ^field) in ^values)
  end

  defp compile_validated_root_field_value(_field, {:not_in, []}), do: :all

  defp compile_validated_root_field_value(field, {:not_in, values}) when is_list(values) do
    dynamic([row], field(row, ^field) not in ^values)
  end

  defp compile_validated_root_field_value(field, {:lt, value}) do
    dynamic([row], field(row, ^field) < ^value)
  end

  defp compile_validated_root_field_value(field, {:lte, value}) do
    dynamic([row], field(row, ^field) <= ^value)
  end

  defp compile_validated_root_field_value(field, {:gt, value}) do
    dynamic([row], field(row, ^field) > ^value)
  end

  defp compile_validated_root_field_value(field, {:gte, value}) do
    dynamic([row], field(row, ^field) >= ^value)
  end

  defp compile_validated_root_field_value(field, {:like, value}) when is_binary(value) do
    dynamic([row], like(field(row, ^field), ^value))
  end

  defp compile_validated_root_field_value(field, {:ilike, value}) when is_binary(value) do
    dynamic([row], ilike(field(row, ^field), ^value))
  end

  defp compile_validated_root_field_value(field, {:near, _params}) do
    raise ArgumentError,
          "filter operator :near requires a declared coordinate filter for field #{inspect(field)}"
  end

  defp combine(:and, :none, _right), do: :none
  defp combine(:and, _left, :none), do: :none
  defp combine(:and, :all, right), do: right
  defp combine(:and, left, :all), do: left
  defp combine(:and, left, right), do: dynamic([row], ^left and ^right)

  defp combine(:or, :all, _right), do: :all
  defp combine(:or, _left, :all), do: :all
  defp combine(:or, :none, right), do: right
  defp combine(:or, left, :none), do: left
  defp combine(:or, left, right), do: dynamic([row], ^left or ^right)

  @doc false
  def integer_operators, do: @integer_operators

  defp prepare_root_field_value!(schema, field, value) do
    case schema.__schema__(:type, field) do
      :integer -> prepare_integer_value!(field, value)
      _type -> value
    end
  end

  defp prepare_integer_value!(field, {operator, values})
       when operator in [:in, :not_in] and is_list(values) do
    {operator, Enum.map(values, &cast_integer!(&1, field))}
  end

  defp prepare_integer_value!(field, {operator, _value}) when operator in [:in, :not_in] do
    raise ArgumentError,
          "filter operator #{inspect(operator)} requires a list for integer field #{inspect(field)}"
  end

  defp prepare_integer_value!(field, {operator, nil}) when operator in @comparison_operators do
    raise ArgumentError,
          "filter operator #{inspect(operator)} requires an integer for field #{inspect(field)}"
  end

  defp prepare_integer_value!(field, {operator, value}) when operator in @integer_operators do
    {operator, cast_integer!(value, field)}
  end

  defp prepare_integer_value!(field, {operator, _value}) when operator in @operators do
    raise ArgumentError,
          "filter operator #{inspect(operator)} is not supported for integer field #{inspect(field)}"
  end

  defp cast_integer!(nil, _field), do: nil

  defp cast_integer!(value, field) do
    case Ecto.Type.cast(:integer, value) do
      {:ok, integer} -> integer
      :error -> raise ArgumentError, "invalid integer filter value #{inspect(value)} for field #{inspect(field)}"
    end
  end

  defp validate_field!(schema, field) when is_atom(field) do
    if field in schema.__schema__(:fields) do
      :ok
    else
      raise ArgumentError, "unknown field #{inspect(field)} for #{inspect(schema)}"
    end
  end

  defp reject_unsupported_operator_shorthand!(:all, _handlers), do: :ok
  defp reject_unsupported_operator_shorthand!(:none, _handlers), do: :ok

  defp reject_unsupported_operator_shorthand!({operator, left, right}, handlers)
       when operator in [:and, :or] do
    reject_unsupported_operator_shorthand!(left, handlers)
    reject_unsupported_operator_shorthand!(right, handlers)
  end

  defp reject_unsupported_operator_shorthand!(filter, handlers) when is_map(filter) do
    Enum.each(filter, fn
      {field, {operator, _value}} when is_atom(operator) and operator not in @operators ->
        if Map.has_key?(handlers, field), do: :ok, else: raise_unsupported_operator!(operator)

      _entry ->
        :ok
    end)
  end

  defp raise_unsupported_operator!(operator) do
    raise ArgumentError, "unsupported filter operator #{inspect(operator)}"
  end
end
