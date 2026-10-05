defmodule Hawk.Writer.RelationshipAuthorization do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Changeset
  alias Hawk.MutationContext

  def authorize(%MutationContext{} = context, relationships, repo) when is_list(relationships) do
    MutationContext.guard(context, fn context ->
      references = references!(context, relationships, repo)

      context
      |> validate_identifiers(references, repo)
      |> MutationContext.guard(&authorize_references(&1, references, repo))
    end)
  end

  defp references!(context, relationships, repo) do
    Enum.flat_map(relationships, fn declaration ->
      {name, override} = declaration!(declaration)
      association = association!(context.model.__struct__, name)
      reader = reader!(context.model.__struct__, association, override, repo)

      case Changeset.get_field(context.changeset, association.owner_key) do
        nil -> []
        value -> [{association, reader, value}]
      end
    end)
  end

  defp authorize_references(context, references, repo) do
    queries =
      Enum.map(references, fn {association, reader, value} ->
        reference_query(association, reader, value, context.authority)
      end)

    authorize_queries(context, queries, repo)
  end

  defp validate_identifiers(context, references, repo) do
    Enum.reduce(references, context, fn {association, _reader, value}, context ->
      type = association.related.__schema__(:type, association.related_key)

      case Ecto.Type.adapter_dump(repo.__adapter__(), type, value) do
        {:ok, _dumped} -> context
        :error -> MutationContext.add_error(context, association.owner_key, "is invalid", validation: :cast)
      end
    end)
  end

  defp declaration!(name) when is_atom(name), do: {name, nil}
  defp declaration!({name, reader}) when is_atom(name) and is_atom(reader), do: {name, reader}

  defp declaration!(declaration) do
    raise ArgumentError, "invalid relationship authorization declaration: #{inspect(declaration)}"
  end

  defp association!(model, name) do
    case model.__schema__(:association, name) do
      %Ecto.Association.BelongsTo{} = association -> association
      _ -> raise ArgumentError, "authorized relationship #{inspect(name)} must be a belongs_to association"
    end
  end

  defp reader!(model, association, override, repo) do
    name = association.field
    reader = override || model_reader!(model, name)
    Code.ensure_compiled!(reader)

    unless function_exported?(reader, :preload_query, 2) and function_exported?(reader, :repo, 0) and
             function_exported?(reader, :schema, 0) do
      raise ArgumentError, "authorized relationship #{inspect(name)} requires a Hawk reader"
    end

    unless reader.repo() == repo do
      raise ArgumentError, "authorized relationship #{inspect(name)} must use the writer's repo"
    end

    unless reader.schema() == association.related do
      raise ArgumentError, "authorized relationship #{inspect(name)} reader must use the associated schema"
    end

    reader
  end

  defp model_reader!(model, name) do
    if function_exported?(model, :__hawk_association_reader__, 1) do
      case model.__hawk_association_reader__(name) do
        {:ok, reader} -> reader
        :error -> missing_reader!(name)
      end
    else
      missing_reader!(name)
    end
  end

  defp missing_reader!(name) do
    raise ArgumentError, "authorized relationship #{inspect(name)} requires an explicit reader or Hawk.Model metadata"
  end

  defp reference_query(association, reader, value, authority) do
    association.related
    |> from(as: :root)
    |> reader.preload_query(authority)
    |> where([root: related], field(related, ^association.related_key) == ^value)
    |> exclude(:select)
    |> select([root: related], field(related, ^association.related_key))
  end

  defp authorize_queries(context, [], _repo), do: context

  defp authorize_queries(context, [first | rest], repo) do
    query =
      Enum.reduce(rest, from(related in subquery(first)), fn reference, query ->
        where(query, exists(subquery(reference)))
      end)

    if repo.exists?(query) do
      context
    else
      context
      |> MutationContext.validate_policy(fn _ -> false end)
      |> Map.update!(:changeset, &Changeset.add_error(&1, :base, "related records are not accessible"))
    end
  end
end
