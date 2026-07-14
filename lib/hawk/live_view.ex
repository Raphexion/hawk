defmodule Hawk.LiveView do
  @moduledoc """
  Small LiveView helper DSL for Hawk resources.

  The generated functions avoid depending on Phoenix at compile time. When used
  inside a Phoenix LiveView, the returned socket shape is still the normal socket;
  in tests or non-Phoenix contexts a `%{assigns: ...}` map works too.
  """

  alias Hawk.LiveView

  defmacro __using__(opts) do
    resource = Keyword.fetch!(opts, :resource)
    as = Keyword.fetch!(opts, :as)
    plural_as = Keyword.get(opts, :plural_as, pluralize(as))

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

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> integer
      _other -> id
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
