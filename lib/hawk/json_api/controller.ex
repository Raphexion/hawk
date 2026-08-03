defmodule Hawk.JsonApi.Controller do
  @moduledoc """
  Phoenix controller helpers for Hawk JSON:API resources.

  Hawk runs behind Phoenix controllers and renders responses through `Plug.Conn`
  directly with the exact `application/vnd.api+json` content type. JSON:API does
  not permit a `charset` media-type parameter. Explicit request `Content-Type`
  values must be JSON:API with only `ext`/`profile` parameters; incompatible
  values return `415`. `Accept` must allow JSON:API (directly or by wildcard),
  otherwise Hawk returns `406`.
  """

  alias Hawk.JsonApi.Controller, as: JsonApiController
  alias Hawk.JsonApi.{Document, Request, Schema}

  @json_api_parameters ["ext", "profile"]
  @accept_parameters ["ext", "profile", "q"]

  @doc """
  Generates a Phoenix JSON:API controller for a Hawk resource.

  Emits `index/2`, `show/2`, `create/2`, `update/2`, `delete/2`,
  `relationship/2`, `related/2`, plus `hawk_action/2` for custom action
  dispatch. The writer is a required sibling for every Hawk
  resource, so the create/update/delete actions are always generated; writes
  are gated by the policy, not by the controller shape.

  ## Options

    * `:resource` (required) — the `Hawk.Resource` facade. The backing model is
      resolved from the facade.
    * `:public` — allow public (anonymous) read access (default `false`).
  """
  defmacro __using__(opts) do
    env = __CALLER__
    resource = Keyword.fetch!(opts, :resource) |> Macro.expand(env)
    require_facade!(resource)
    model = resource.__hawk_resource__(:model)
    validate_json_api_enabled!(resource)
    public? = Keyword.get(opts, :public, false)
    reader = resource.__hawk_resource__(:reader)

    quote do
      def index(conn, params) do
        JsonApiController.index(
          conn,
          unquote(resource),
          unquote(model),
          unquote(reader),
          params,
          unquote(public?)
        )
      end

      def show(conn, params) do
        JsonApiController.show(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      unquote(quote_writer_actions(resource, model, public?))
      unquote(quote_custom_action(resource, model, public?))

      def relationship(conn, params) do
        JsonApiController.relationship(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def related(conn, params) do
        JsonApiController.related(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end
    end
  end

  defp require_facade!(resource) do
    case Code.ensure_compiled(resource) do
      {:module, ^resource} ->
        if function_exported?(resource, :__hawk_resource__, 1) do
          :ok
        else
          raise ArgumentError,
                "Hawk JSON:API controller resource #{inspect(resource)} must be a Hawk.Resource facade"
        end

      _ ->
        raise ArgumentError,
              "Hawk JSON:API controller resource #{inspect(resource)} is not available"
    end
  end

  defp quote_writer_actions(resource, model, public?) do
    quote do
      def create(conn, params) do
        JsonApiController.create(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def update(conn, params) do
        JsonApiController.update(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def delete(conn, params) do
        JsonApiController.delete(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end
    end
  end

  defp quote_custom_action(resource, model, public?) do
    quote do
      def hawk_action(conn, params) do
        JsonApiController.action(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end
    end
  end

  defp validate_json_api_enabled!(resource) do
    if resource.__hawk_resource__(:json_api) == false do
      raise ArgumentError,
            "Hawk JSON:API controller resource #{inspect(resource)} has json_api disabled"
    end
  end

  @doc false
  def index(conn, resource, _model, reader, params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      fields = Request.sparse_fieldsets(params)

      opts =
        params
        |> Request.request_options(reader: reader)
        |> Keyword.put(:authority, authority)
        |> Keyword.put(:context, request_context(conn))

      document =
        Document.document(resource.all(opts),
          preloads: Keyword.get(opts, :preloads, []),
          context: Keyword.get(opts, :context, %{}),
          page: Keyword.get(opts, :page),
          fields: fields
        )

      json(conn, 200, document)
    end)
  end

  @doc false
  def show(conn, resource, model, %{"id" => id} = params, public? \\ false) do
    do_show(conn, resource, model, id, params, public?)
  end

  defp do_show(conn, resource, _model, id, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      fields = Request.sparse_fieldsets(params)

      case Request.member_id!(id) do
        {:uuid, uuid} -> show_by_uuid(conn, resource, authority, context, uuid, fields)
        {:short_id, prefix} -> show_by_short_id(conn, resource, authority, context, prefix, fields)
      end
    end)
  end

  defp show_by_uuid(conn, resource, authority, context, uuid, fields) do
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

    case resource.one(authority: authority, context: context, filter: %{identity => uuid}) do
      {:ok, model} ->
        json(
          conn,
          200,
          Document.document(model,
            context: context,
            links: true,
            fields: fields
          )
        )

      :not_found ->
        json(conn, 404, not_found(resource))
    end
  end

  defp show_by_short_id(conn, resource, authority, context, prefix, fields) do
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

    case resource.all(
           authority: authority,
           context: context,
           filter: Request.short_id_filter(prefix, identity),
           page: %{size: 2}
         ) do
      [model] ->
        json(
          conn,
          200,
          Document.document(model,
            context: context,
            links: true,
            fields: fields
          )
        )

      [] ->
        json(conn, 404, not_found(resource))

      [_first, _second | _rest] ->
        json(conn, 400, bad_request("id prefix #{inspect(prefix)} is ambiguous"))
    end
  end

  defp model_module(%module{}), do: module

  defp primary_result(results, primary_model) do
    Enum.find_value(results, fn {_name, value} ->
      if is_struct(value, primary_model), do: value
    end)
  end

  @doc false
  def create(conn, resource, model, params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)

      Request.validate_document!(params, model, :creatable)

      params
      |> Request.attributes(model, :creatable)
      |> resource.create(authority)
      |> respond(conn, resource, model, 201)
    end)
  end

  @doc false
  def update(conn, resource, model, %{"id" => id} = params, public? \\ false) do
    do_update(conn, resource, model, id, params, public?)
  end

  defp do_update(conn, resource, model, id, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

      path_id = normalize_id(id)

      case resource.one(authority: authority, context: context, filter: %{identity => path_id}) do
        {:ok, existing} ->
          Request.validate_document!(params, model, :updatable, path_id: path_id)

          params
          |> Request.attributes(model, :updatable)
          |> then(&resource.update(existing, &1, authority))
          |> respond(conn, resource, model, 200)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  @doc false
  def delete(conn, resource, _model, %{"id" => id}, public? \\ false) do
    do_delete(conn, resource, id, public?)
  end

  defp do_delete(conn, resource, id, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

      case resource.one(authority: authority, context: context, filter: %{identity => normalize_id(id)}) do
        {:ok, existing} -> respond_delete(conn, resource, existing, authority)
        :not_found -> json(conn, 404, not_found(resource))
      end
    end)
  end

  defp respond_delete(conn, resource, existing, authority) do
    case resource.delete(existing, authority) do
      {:ok, _deleted} -> no_content(conn)
      :ok -> no_content(conn)
      result -> respond(result, conn, resource, model_module(existing), 200)
    end
  end

  @doc false
  def action(
        conn,
        resource,
        _model,
        %{"id" => id, "action" => action_name} = params,
        public? \\ false
      ) do
    do_action(conn, resource, id, action_name, params, public?)
  end

  defp do_action(conn, resource, id, action_name, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

      case resource.one(authority: authority, context: context, filter: %{identity => normalize_id(id)}) do
        {:ok, existing} ->
          respond_action(conn, resource, action_name, existing, params, authority)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  @doc false
  def relationship(
        conn,
        resource,
        model,
        %{"id" => id, "relationship" => relationship_name},
        public? \\ false
      ) do
    do_relationship(conn, resource, model, id, relationship_name, public?)
  end

  defp do_relationship(conn, resource, model, id, relationship_name, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

      relationship = Schema.relationship_key!(model, relationship_name)
      association = model.__schema__(:association, relationship)
      preloads = if match?(%{cardinality: :many}, association), do: [relationship], else: []

      case resource.one(
             authority: authority,
             context: context,
             filter: %{identity => normalize_id(id)},
             preloads: preloads
           ) do
        {:ok, loaded} ->
          json(
            conn,
            200,
            Document.relationship_document(loaded, relationship_name)
          )

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  @doc false
  def related(
        conn,
        resource,
        model,
        %{"id" => id, "relationship" => relationship_name} = params,
        public? \\ false
      ) do
    do_related(conn, resource, model, id, relationship_name, params, public?)
  end

  defp do_related(conn, resource, model, id, relationship_name, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      fields = Request.sparse_fieldsets(params)
      identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

      relationship =
        Schema.relationship_key!(model, relationship_name)

      case resource.one(
             authority: authority,
             context: context,
             filter: %{identity => normalize_id(id)},
             preloads: [relationship]
           ) do
        {:ok, model} ->
          json(
            conn,
            200,
            Document.related_document(model, relationship_name, fields: fields)
          )

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  defp respond_action(conn, resource, action_name, existing, params, authority) do
    if dry_run?(params) do
      respond_action_dry_run(conn, resource, action_name, existing, Map.get(params, "meta", %{}), authority)
    else
      dispatch_action(conn, resource, action_name, existing, Map.get(params, "meta", %{}), authority)
    end
  end

  defp dispatch_action(conn, resource, action_name, existing, meta, authority) do
    case Hawk.Actions.dispatch(resource, action_name, existing, meta, authority) do
      :unknown_action ->
        json(conn, 404, action_not_found(resource, action_name))

      {:ok, results} when is_map(results) and not is_struct(results) ->
        # A two-phase Action returns a map of step name to model. Render the
        # primary resource (the one the action is anchored to) as the JSON:API
        # document; secondary effects are not inlined here.
        primary = primary_result(results, resource.__hawk_resource__(:model))
        respond({:ok, primary}, conn, resource, model_module(existing), 200)

      result ->
        respond(result, conn, resource, model_module(existing), 200)
    end
  end

  defp dry_run?(params) do
    case Map.get(params, "dry-run") do
      nil -> false
      value when value in [true, "true", "1", 1] -> true
      _ -> false
    end
  end

  defp respond_action_dry_run(conn, resource, action_name, existing, meta, authority) do
    actions_module = Hawk.Actions.actions_module(resource)

    with module when is_atom(module) and module != false <- actions_module,
         {:ok, actions} <- fetch_actions(module),
         {:ok, metadata} <- Map.fetch(actions, action_name) do
      change_fn = change_handler_fn(metadata)

      cond do
        function_exported?(module, change_fn, 3) ->
          changesets =
            apply(module, change_fn, [
              existing,
              Hawk.Actions.atomize_params(meta, metadata),
              authority
            ])

          render_dry_run(conn, changesets)

        metadata.build == nil ->
          json(conn, 400, bad_request("action #{inspect(action_name)} is run-only and does not support dry-run"))

        true ->
          json(conn, 404, action_not_found(resource, action_name))
      end
    else
      _ -> json(conn, 404, action_not_found(resource, action_name))
    end
  end

  defp change_handler_fn(%{change_handler: handler}), do: String.to_atom("#{handler}_change")
  defp change_handler_fn(%{handler: handler}), do: String.to_atom("#{handler}_change")

  defp fetch_actions(actions_module) do
    if function_exported?(actions_module, :__hawk_actions__, 0) do
      {:ok, actions_module.__hawk_actions__()}
    else
      :error
    end
  end

  defp render_dry_run(conn, changesets) do
    errors = Enum.flat_map(changesets, &dry_run_errors/1)

    if errors == [],
      do: json(conn, 200, %{data: nil, meta: %{"dry-run": true}}),
      else: json(conn, 422, %{errors: errors})
  end

  defp dry_run_errors({step, changeset}) do
    changeset
    |> Ecto.Changeset.traverse_errors(&error_detail/1)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(
        messages,
        &%{
          status: "422",
          code: "invalid",
          title: "Validation error",
          detail: &1,
          source: %{pointer: "/data/#{step}/#{field}"}
        }
      )
    end)
  end

  defp error_detail({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value), global: false)
    end)
  end

  defp respond({:ok, returned_model}, conn, _resource, _model, status) do
    json(
      conn,
      status,
      Document.document(returned_model,
        context: request_context(conn)
      )
    )
  end

  defp respond(:ok, conn, _resource, _model, status), do: json(conn, status, %{data: nil})

  defp respond({:not_authorized, _context} = result, conn, _resource, _model, _status),
    do: json(conn, 403, Hawk.Errors.to_json_api(result))

  defp respond({:invalid, _context} = result, conn, _resource, _model, _status),
    do: json(conn, 422, Hawk.Errors.to_json_api(result))

  defp respond({:error, _message} = result, conn, _resource, _model, _status),
    do: json(conn, 500, Hawk.Errors.to_json_api(result))

  defp with_error_boundary(conn, fun) when is_function(fun, 0) do
    case negotiate_media_type(conn) do
      :ok -> fun.()
      {:error, status, body} -> json(conn, status, body)
    end
  rescue
    error in ArgumentError -> json(conn, 400, bad_request(error.message))
  end

  defp negotiate_media_type(conn) do
    with :ok <- validate_content_type(conn),
         :ok <- validate_accept(conn) do
      :ok
    end
  end

  defp validate_content_type(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [] ->
        :ok

      [content_type] ->
        case Plug.Conn.Utils.media_type(content_type) do
          {:ok, "application", "vnd.api+json", params} ->
            if supported_params?(params, @json_api_parameters),
              do: :ok,
              else: media_type_error(415, :unsupported_media_type, "Unsupported media type")

          _other ->
            media_type_error(415, :unsupported_media_type, "Unsupported media type")
        end

      _multiple ->
        media_type_error(415, :unsupported_media_type, "Unsupported media type")
    end
  end

  defp validate_accept(conn) do
    case Plug.Conn.get_req_header(conn, "accept") do
      [] ->
        :ok

      headers ->
        acceptable? =
          headers
          |> Enum.flat_map(&String.split(&1, ",", trim: true))
          |> Enum.flat_map(&json_api_media_range/1)
          |> accepts_json_api?()

        if acceptable?, do: :ok, else: media_type_error(406, :not_acceptable, "Not acceptable")
    end
  end

  defp json_api_media_range(media_range) do
    case Plug.Conn.Utils.media_type(media_range) do
      {:ok, "*", "*", params} ->
        media_range_quality(params, ["q"], 0)

      {:ok, "application", "*", params} ->
        media_range_quality(params, ["q"], 1)

      {:ok, "application", "vnd.api+json", params} ->
        media_range_quality(params, @accept_parameters, 2)

      _other ->
        []
    end
  end

  defp media_range_quality(params, supported, specificity) do
    with true <- supported_params?(params, supported),
         {:ok, quality} <- quality(params) do
      [{specificity, quality}]
    else
      _unsupported_or_invalid -> []
    end
  end

  defp accepts_json_api?([]), do: false

  defp accepts_json_api?(ranges) do
    highest_specificity = ranges |> Enum.map(&elem(&1, 0)) |> Enum.max()

    ranges
    |> Enum.filter(&(elem(&1, 0) == highest_specificity))
    |> Enum.any?(&(elem(&1, 1) > 0.0))
  end

  defp supported_params?(params, supported) do
    params
    |> Map.keys()
    |> Enum.all?(&Enum.member?(supported, &1))
  end

  defp quality(%{"q" => quality}) do
    case Float.parse(quality) do
      {value, ""} when value >= 0.0 and value <= 1.0 -> {:ok, value}
      _invalid -> :error
    end
  end

  defp quality(_params), do: {:ok, 1.0}

  defp media_type_error(status, code, title) do
    error = %Hawk.Error{status: status, code: code, title: title, detail: title}
    {:error, status, Hawk.Errors.to_json_api(error)}
  end

  defp bad_request(message) do
    message
    |> Hawk.Error.bad_request()
    |> Hawk.Errors.to_json_api()
  end

  defp authority!(%{assigns: %{hawk_authority: authority}}, _public?), do: authority
  defp authority!(_conn, true), do: Hawk.Authority.public()

  defp request_context(conn), do: %{locale: request_locale(conn)}

  defp request_locale(conn) do
    header(conn, "x-locale") || accept_language_locale(header(conn, "accept-language")) || "en"
  end

  defp header(%Plug.Conn{} = conn, name) do
    conn
    |> Plug.Conn.get_req_header(name)
    |> List.first()
  end

  defp accept_language_locale(nil), do: nil

  defp accept_language_locale(header) do
    header
    |> String.split(",")
    |> List.first()
    |> case do
      nil -> nil
      locale -> locale |> String.split(";") |> List.first() |> String.split("-") |> List.first()
    end
  end

  defp json(%Plug.Conn{} = conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/vnd.api+json", nil)
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp no_content(%Plug.Conn{} = conn), do: Plug.Conn.send_resp(conn, 204, "")

  defp not_found(resource) do
    name =
      resource |> Module.split() |> List.last() |> Macro.underscore() |> String.trim_trailing("s")

    %{
      errors: [
        %{status: "404", code: "not_found", title: "Not found", detail: "#{name} was not found"}
      ]
    }
  end

  defp action_not_found(resource, action_name) do
    name =
      resource |> Module.split() |> List.last() |> Macro.underscore() |> String.trim_trailing("s")

    %{
      errors: [
        %{
          status: "404",
          code: "action_not_found",
          title: "Not found",
          detail: "#{action_name} is not a supported action for #{name}"
        }
      ]
    }
  end

  defp normalize_id(id), do: Request.validate_uuid!(id)
end
