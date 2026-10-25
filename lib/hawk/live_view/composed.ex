defmodule Hawk.LiveView.Composed do
  @moduledoc """
  Coordinates policy-safe refreshes for LiveViews composed from multiple Hawk resources.

  This module only subscribes and re-reads. The host application decides how to
  apply returned values to assigns, streams, or page-specific UI state.
  """

  @type resource_entry :: {atom(), [resource: module()]}
  @type refresh_result ::
          {:ok, %{key: atom(), mode: :record | :collection | :page, value: term()}}
          | {:ignore, :undeclared_resource | :inactive_resource}

  @doc """
  Subscribes to every resource declared by the composed page module.

  Subscription remains routing only. A later `refresh/4` call re-reads through
  the socket authority.
  """
  @spec subscribe(Phoenix.LiveView.Socket.t(), module()) :: Phoenix.LiveView.Socket.t()
  def subscribe(socket, page_module) when is_struct(socket, Phoenix.LiveView.Socket) do
    page_module
    |> resources()
    |> Enum.reduce(socket, fn {_key, opts}, socket ->
      Hawk.LiveView.subscribe(socket, Keyword.fetch!(opts, :resource))
    end)
  end

  @doc """
  Re-reads the resource affected by `event` using the page's declared spec.

  The result is intentionally not applied to the socket. Applications can
  assign a record, replace a collection, or reset a LiveView stream according
  to their own presentation and pagination rules.
  """
  @spec refresh(Phoenix.LiveView.Socket.t(), module(), Hawk.PubSub.Event.t(), keyword()) ::
          refresh_result()
  def refresh(socket, page_module, %Hawk.PubSub.Event{resource: resource}, opts \\ []) do
    with {:ok, {key, resource_opts}} <- find_resource(page_module, resource),
         {:ok, spec} <- active_spec(socket, key),
         {:ok, value, mode} <- reread(resource_opts, spec, authority(socket, opts)) do
      {:ok, %{key: key, mode: mode, value: value}}
    else
      :not_found -> {:ignore, :undeclared_resource}
      :inactive -> {:ignore, :inactive_resource}
    end
  end

  defp find_resource(page_module, resource) do
    case Enum.find(resources(page_module), fn {_key, opts} -> Keyword.fetch!(opts, :resource) == resource end) do
      nil -> :not_found
      entry -> {:ok, entry}
    end
  end

  defp active_spec(socket, key) do
    case Map.get(socket.assigns, :hawk_page_specs, %{}) |> Map.fetch(key) do
      {:ok, spec} -> {:ok, spec}
      :error -> :inactive
    end
  end

  defp reread(resource_opts, {mode, opts}, authority) when mode in [:one, :all, :page] do
    resource = Keyword.fetch!(resource_opts, :resource)
    opts = opts |> Keyword.put(:authority, authority)

    case mode do
      :one ->
        case resource.one(opts) do
          {:ok, value} -> {:ok, value, :record}
          :not_found -> {:ok, :not_found, :record}
        end

      :all ->
        {:ok, resource.all(opts), :collection}

      :page ->
        {:ok, resource.page(opts), :page}
    end
  end

  defp authority(socket, opts) do
    Keyword.get(opts, :authority) ||
      Map.get(socket.assigns, :hawk_authority) ||
      Map.get(socket.assigns, :hawk_page_authority) ||
      Hawk.Authority.public()
  end

  defp resources(page_module) do
    page_module.__hawk_live_view_page_resources__()
  end
end
