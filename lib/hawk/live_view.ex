defmodule Hawk.LiveView do
  @moduledoc """
  Small Phoenix LiveView helper DSL for Hawk resources.

  Hawk is intended to run in Phoenix LiveViews. The generated helpers delegate to
  `Phoenix.Component.assign/3` when available; plain map sockets remain supported
  as a lightweight test boundary.
  """

  alias Hawk.LiveView

  defmacro __using__(opts) do
    env = __CALLER__
    resource = Keyword.fetch!(opts, :resource) |> Macro.expand(env)
    validate_live_view_enabled!(resource)
    as = Keyword.get(opts, :as) || infer_as!(resource)
    plural_as = Keyword.get(opts, :plural_as) || infer_plural_as(resource, as)
    capabilities = live_view_capabilities(resource)

    quote do
      def assign_index(socket, authority, opts \\ []) do
        LiveView.assign_index(
          socket,
          unquote(resource),
          unquote(as),
          unquote(plural_as),
          authority,
          opts
        )
      end

      def assign_show(socket, authority, id, opts \\ []) do
        LiveView.assign_show(socket, unquote(resource), unquote(as), authority, id, opts)
      end

      unquote(quote_delete_handler(resource, as, plural_as, capabilities))
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

  defp quote_delete_handler(_resource, _as, _plural_as, %{writer: false}), do: []

  defp quote_delete_handler(resource, as, plural_as, _capabilities) do
    quote do
      def handle_event("hawk:delete", params, socket) do
        LiveView.handle_delete(
          socket,
          unquote(resource),
          unquote(as),
          unquote(plural_as),
          params
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
    results = resource.all(Keyword.put(opts, :authority, authority))

    socket
    |> assign(:hawk_resource, as)
    |> assign(:hawk_page, Keyword.get(opts, :page, %{}))
    |> assign(plural_as, results)
  end

  def assign_show(socket, resource, as, authority, id, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:authority, authority)
      |> Keyword.update(:filter, %{id: normalize_id(id)}, &Map.put(&1, :id, normalize_id(id)))

    case resource.one(opts) do
      {:ok, model} ->
        socket
        |> assign(:hawk_resource, as)
        |> assign(as, model)

      :not_found ->
        assign(socket, :hawk_error, %{
          base: ["#{String.replace(to_string(as), "_", " ")} was not found"]
        })
    end
  end

  def handle_delete(socket, resource, as, plural_as, %{"id" => id, "authority" => authority}) do
    case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
      {:ok, model} ->
        case resource.delete(model, authority) do
          {:ok, _model} -> {:noreply, assign_index(socket, resource, as, plural_as, authority)}
          result -> {:noreply, assign(socket, :hawk_error, live_error(result))}
        end

      :not_found ->
        {:noreply,
         assign(socket, :hawk_error, %{
           base: ["#{String.replace(to_string(as), "_", " ")} was not found"]
         })}
    end
  end

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
