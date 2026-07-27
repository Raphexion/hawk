defmodule Hawk.LiveView.Page do
  @moduledoc """
  Composes multiple Hawk resources for richer LiveView pages.

  Use this when one LiveView owns a small workspace instead of a single resource,
  for example a course page that also manages students and grades.
  """

  alias Hawk.LiveView.Page

  defmacro __using__(opts) do
    resources =
      opts
      |> Keyword.fetch!(:resources)
      |> Enum.map(fn {key, resource_opts} ->
        {key, Keyword.update!(resource_opts, :resource, &Macro.expand(&1, __CALLER__))}
      end)

    sections = opts |> Keyword.get(:sections, []) |> normalize_sections()

    quote do
      def assign_page(socket, authority, specs) do
        Page.assign_page(socket, unquote(Macro.escape(resources)), authority, specs)
      end

      def hawk_page_sections, do: unquote(Macro.escape(sections))

      def hawk_page_section(id) do
        Enum.find(hawk_page_sections(), &(&1.id == id))
      end

      def handle_event("hawk:delete", params, socket) do
        Page.handle_delete(socket, unquote(Macro.escape(resources)), params)
      end
    end
  end

  defp normalize_sections(sections) do
    Enum.map(sections, fn {id, opts} ->
      opts
      |> Map.new()
      |> Map.put(:id, id)
    end)
  end

  def assign_page(socket, resources, authority, specs) when is_list(specs) do
    resource_keys = Keyword.keys(specs)

    socket
    |> assign(:hawk_page_authority, authority)
    |> assign(:hawk_page_specs, normalize_specs(specs))
    |> assign(:hawk_page_resources, resource_keys)
    |> assign_many(resources, authority, specs)
  end

  def handle_delete(socket, resources, %{"resource" => resource_name, "id" => id}) do
    key = fetch_resource_key!(resources, resource_name)
    authority = Map.fetch!(socket.assigns, :hawk_page_authority)
    specs = Map.fetch!(socket.assigns, :hawk_page_specs)

    unless Map.has_key?(specs, key) do
      raise ArgumentError, "LiveView page resource #{inspect(key)} is not active on this page"
    end

    resource = fetch_resource!(resources, key)
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

    case resource.one(authority: authority, filter: %{identity => normalize_id(id)}) do
      {:ok, model} ->
        case resource.delete(model, authority) do
          {:ok, _model} -> {:noreply, refresh_page(socket, resources, authority)}
          result -> {:noreply, put_error(socket, key, live_error(result))}
        end

      :not_found ->
        {:noreply, put_error(socket, key, %{base: ["#{singular(key)} was not found"]})}
    end
  end

  defp assign_many(socket, resources, authority, specs) do
    Enum.reduce(specs, socket, fn {key, spec}, socket ->
      assign_resource(socket, resources, authority, key, spec)
    end)
  end

  defp assign_resource(socket, resources, authority, key, {mode, opts})
       when mode in [:one, :all] do
    resource = fetch_resource!(resources, key)
    opts = Keyword.put(opts, :authority, authority)

    case {mode, run_resource(resource, mode, opts)} do
      {:one, {:ok, model}} -> assign(socket, key, model)
      {:one, :not_found} -> put_error(socket, key, %{base: ["#{singular(key)} was not found"]})
      {:all, models} -> assign(socket, key, models)
    end
  end

  defp run_resource(resource, :one, opts), do: resource.one(opts)
  defp run_resource(resource, :all, opts), do: resource.all(opts)

  defp refresh_page(socket, resources, authority) do
    specs = Map.get(socket.assigns, :hawk_page_specs, %{})
    assign_many(socket, resources, authority, Map.to_list(specs))
  end

  defp normalize_specs(specs) do
    Map.new(specs, fn {key, {mode, opts}} -> {key, {mode, opts}} end)
  end

  defp fetch_resource_key!(resources, resource_name) when is_binary(resource_name) do
    case Enum.find(resources, fn {key, _opts} -> to_string(key) == resource_name end) do
      {key, _opts} -> key
      nil -> raise ArgumentError, "unknown LiveView page resource #{inspect(resource_name)}"
    end
  end

  defp fetch_resource!(resources, key) do
    case Keyword.fetch(resources, key) do
      {:ok, opts} -> Keyword.fetch!(opts, :resource)
      :error -> raise ArgumentError, "unknown LiveView page resource #{inspect(key)}"
    end
  end

  defp put_error(socket, key, error) do
    errors = socket.assigns |> Map.get(:hawk_errors, %{}) |> Map.put(key, error)
    assign(socket, :hawk_errors, errors)
  end

  defp live_error(result) do
    case Hawk.Errors.to_live_view(result) do
      {:error, errors} -> errors
    end
  end

  defp singular(key) do
    key
    |> to_string()
    |> String.trim_trailing("s")
    |> String.replace("_", " ")
  end

  defp assign(socket, key, value), do: Phoenix.Component.assign(socket, key, value)

  defp normalize_id(id), do: id
end
