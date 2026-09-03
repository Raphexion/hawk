defmodule Hawk.JsonApi.QueryController do
  @moduledoc """
  Generic JSON:API adapter for Hawk queries returning resource collections.
  """

  use Phoenix.Controller, formats: []

  alias Hawk.JsonApi.{ControllerSupport, Document, Request}

  @doc false
  def index(conn, params) do
    query = Map.fetch!(conn.private, :hawk_query)
    public? = Map.get(conn.private, :hawk_public?, false)

    ControllerSupport.with_error_boundary(
      conn,
      fn ->
        metadata = Hawk.Query.metadata(query)
        source = metadata.source
        model = source.__hawk_resource__(:model)
        reader = source.__hawk_resource__(:reader)
        authority = ControllerSupport.authority!(conn, public?)
        fields = Request.sparse_fieldsets(params)
        select = source.json_api_select_fields(authority, fields)

        opts =
          params
          |> Request.request_options(reader: reader, model: model, authority: authority)
          |> Keyword.put(:authority, authority)
          |> Keyword.put(:context, ControllerSupport.request_context(conn))
          |> Keyword.put(:fields, fields)
          |> Keyword.put(:params, query_params(params))
          |> Keyword.put(:select, select)

        case query.page(opts) do
          {:error, %Hawk.Error{} = error} ->
            ControllerSupport.json(conn, error.status, Hawk.Errors.to_json_api(error))

          result ->
            document =
              Document.document(result.entries,
                authority: authority,
                preloads: Keyword.get(opts, :preloads, []),
                context: Keyword.get(opts, :context, %{}),
                page: result.page,
                fields: fields,
                has_more: result.has_more?,
                next_cursor: result.next_cursor,
                total_count: result.total_count
              )

            ControllerSupport.json(conn, 200, document)
        end
      end,
      extra_query_parameters: ["query"]
    )
  end

  defp query_params(params) do
    case Map.get(params, "query", %{}) do
      query when is_map(query) -> query
      _other -> raise ArgumentError, "query must be an object"
    end
  end
end
