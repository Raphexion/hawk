defmodule Hawk.LiveView do
  @moduledoc """
  Small Phoenix LiveView helper DSL for Hawk resources.

  Hawk is intended to run in Phoenix LiveViews. The generated helpers delegate to
  `Phoenix.Component.assign/3` when available; plain map sockets remain supported
  as a lightweight test boundary.
  """

  alias Hawk.{Filter, LiveView}

  defmacro __using__(opts) do
    env = __CALLER__
    resource = Keyword.fetch!(opts, :resource) |> Macro.expand(env)
    validate_live_view_enabled!(resource)
    as = Keyword.get(opts, :as) || infer_as!(resource)
    plural_as = Keyword.get(opts, :plural_as) || infer_plural_as(resource, as)
    capabilities = live_view_capabilities(resource)
    live_view = live_view_metadata(resource)

    quote do
      def assign_index(socket, authority, opts \\ []) do
        LiveView.assign_index(
          socket,
          unquote(resource),
          unquote(as),
          unquote(plural_as),
          authority,
          opts,
          unquote(Macro.escape(live_view))
        )
      end

      def assign_show(socket, authority, id, opts \\ []) do
        LiveView.assign_show(
          socket,
          unquote(resource),
          unquote(as),
          authority,
          id,
          opts,
          unquote(Macro.escape(live_view))
        )
      end

      unquote(quote_delete_handler(resource, as, plural_as, capabilities, live_view))
    end
  end

  defp live_view_capabilities(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) do
      resource.__hawk_resource__(:capabilities)
    else
      %{writer: true}
    end
  end

  defp quote_delete_handler(_resource, _as, _plural_as, %{writer: false}, _live_view), do: []

  defp quote_delete_handler(resource, as, plural_as, _capabilities, live_view) do
    quote do
      def handle_event("hawk:delete", params, socket) do
        LiveView.handle_delete(
          socket,
          unquote(resource),
          unquote(as),
          unquote(plural_as),
          params,
          unquote(Macro.escape(live_view))
        )
      end
    end
  end

  defp validate_live_view_enabled!(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) and
         resource.__hawk_resource__(:live_view) == false do
      raise ArgumentError, "Hawk LiveView resource #{inspect(resource)} has live_view disabled"
    end
  end

  defp infer_as!(resource) do
    cond do
      Code.ensure_compiled(resource) != {:module, resource} ->
        raise ArgumentError, "Hawk LiveView resource #{inspect(resource)} is not available"

      function_exported?(resource, :__hawk_resource__, 1) ->
        resource
        |> live_view_metadata()
        |> Map.get(:as, model_as(resource.__hawk_resource__(:model)))

      true ->
        raise ArgumentError,
              "Hawk LiveView requires :as when resource #{inspect(resource)} is not a Hawk.Resource facade"
    end
  end

  defp infer_plural_as(resource, as) do
    resource
    |> live_view_metadata()
    |> Map.get(:plural_as, pluralize(as))
  end

  defp live_view_metadata(resource) do
    if function_exported?(resource, :__hawk_resource__, 1) do
      case resource.__hawk_resource__(:live_view) do
        false -> %{}
        live_view -> live_view.__hawk_live_view__()
      end
    else
      %{}
    end
  end

  defp model_as(model) do
    model
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  def assign_index(socket, resource, as, plural_as, authority, opts \\ []) do
    assign_index(socket, resource, as, plural_as, authority, opts, %{})
  end

  def assign_index(socket, resource, as, plural_as, authority, opts, live_view) do
    opts =
      opts
      |> Keyword.delete(:params)
      |> put_live_view_filter(Keyword.get(opts, :params, %{}), live_view)

    results = resource.all(Keyword.put(opts, :authority, authority))

    socket
    |> assign(:hawk_resource, as)
    |> assign(:hawk_page, Keyword.get(opts, :page, %{}))
    |> assign(:hawk_table, live_view_table(live_view))
    |> assign(plural_as, results)
  end

  def assign_show(socket, resource, as, authority, id, opts \\ []) do
    assign_show(socket, resource, as, authority, id, opts, %{})
  end

  def assign_show(socket, resource, as, authority, id, opts, live_view) do
    opts =
      opts
      |> Keyword.put(:authority, authority)
      |> Keyword.update(:filter, %{id: normalize_id(id)}, &Map.put(&1, :id, normalize_id(id)))

    case resource.one(opts) do
      {:ok, model} ->
        socket
        |> assign(:hawk_resource, as)
        |> assign(:hawk_fields, live_view_fields(live_view))
        |> assign(as, model)

      :not_found ->
        assign(socket, :hawk_error, %{
          base: ["#{String.replace(to_string(as), "_", " ")} was not found"]
        })
    end
  end

  def handle_delete(socket, resource, as, plural_as, params) do
    handle_delete(socket, resource, as, plural_as, params, %{})
  end

  def handle_delete(
        socket,
        resource,
        as,
        plural_as,
        %{"id" => id, "authority" => authority},
        live_view
      ) do
    case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
      {:ok, model} ->
        case resource.delete(model, authority) do
          {:ok, _model} ->
            {:noreply, assign_index(socket, resource, as, plural_as, authority, [], live_view)}

          result ->
            {:noreply, assign(socket, :hawk_error, live_error(result))}
        end

      :not_found ->
        {:noreply,
         assign(socket, :hawk_error, %{
           base: ["#{String.replace(to_string(as), "_", " ")} was not found"]
         })}
    end
  end

  defp put_live_view_filter(opts, params, live_view) do
    case parse_live_view_filter(params, live_view) do
      :all -> opts
      filter -> Keyword.update(opts, :filter, filter, &Filter.and(&1, filter))
    end
  end

  defp parse_live_view_filter(params, live_view) when is_map(params) do
    params
    |> Map.get("filter", %{})
    |> parse_live_view_filter_map(live_view_filters(live_view))
  end

  defp parse_live_view_filter(_params, _live_view), do: :all

  defp parse_live_view_filter_map(filter, _allowed) when filter in [nil, %{}], do: :all

  defp parse_live_view_filter_map(filter, allowed) when is_map(filter) do
    allowed_by_name = Map.new(allowed, &{to_string(&1), &1})

    Map.new(filter, fn {name, value} ->
      case Map.fetch(allowed_by_name, name) do
        {:ok, key} -> {key, parse_live_view_filter_value(value)}
        :error -> raise ArgumentError, "unknown LiveView filter #{inspect(name)}"
      end
    end)
  end

  defp parse_live_view_filter_map(_filter, _allowed),
    do: raise(ArgumentError, "LiveView filter params must be an object")

  defp parse_live_view_filter_value(%{} = value) when map_size(value) == 1 do
    [{operator, operand}] = Map.to_list(value)
    {parse_live_view_filter_operator!(operator), operand}
  end

  defp parse_live_view_filter_value(value), do: value

  defp parse_live_view_filter_operator!(operator)
       when operator in ["eq", "neq", "in", "not_in", "lt", "lte", "gt", "gte", "like", "ilike"] do
    String.to_existing_atom(operator)
  end

  defp parse_live_view_filter_operator!(operator) when is_atom(operator), do: operator

  defp parse_live_view_filter_operator!(operator),
    do: raise(ArgumentError, "unsupported LiveView filter operator #{inspect(operator)}")

  defp live_view_filters(live_view),
    do: live_view |> Map.get(:index, %{}) |> Map.get(:filters, [])

  defp live_view_table(live_view), do: live_view |> Map.get(:index, %{}) |> Map.get(:table, [])
  defp live_view_fields(live_view), do: live_view |> Map.get(:show, %{}) |> Map.get(:fields, [])

  defp live_error(result) do
    case Hawk.Errors.to_live_view(result) do
      {:error, errors} -> errors
    end
  end

  defp assign(socket, key, value) do
    phoenix_component = Module.concat([Phoenix, Component])

    if Code.ensure_loaded?(phoenix_component) and
         function_exported?(phoenix_component, :assign, 3) do
      phoenix_component.assign(socket, key, value)
    else
      assigns = Map.get(socket, :assigns, %{})
      Map.put(socket, :assigns, Map.put(assigns, key, value))
    end
  end

  defp normalize_id(id), do: id

  defp pluralize(as) do
    as
    |> to_string()
    |> Kernel.<>("s")
    |> String.to_atom()
  end
end
