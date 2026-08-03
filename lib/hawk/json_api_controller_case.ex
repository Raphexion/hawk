defmodule Hawk.JsonApiControllerCase do
  @moduledoc """
  ExUnit helper for exercising Hawk JSON:API controller defaults across roles.

  The case intentionally covers the boring matrix every resource should get for
  free: role x index/show/create/update/delete. Resource-specific behaviour can
  be tested by adding ordinary tests in the same module and using the imported
  helpers.

      defmodule MyAppWeb.CoursesControllerTest do
        use Hawk.JsonApiControllerCase,
          controller: MyAppWeb.CoursesController,
          resource: MyApp.Courses,
          model: MyApp.Course,
          repo: MyApp.Repo

        pre_authorities do
          %{teacher: MyApp.Factory.user()}
        end

        authorities pre_authorities do
          %{
            principal: Hawk.Authority.new(:principal, 1),
            student: Hawk.Authority.new(:student, 2, scopes: %{school_id: pre_authorities.school_id})
          }
        end

        pre_sample pre_authorities, authorities do
          %{school: %MyApp.School{id: pre_authorities.school_id}, teacher: authorities.student}
        end

        sample pre_authorities, authorities, known, index do
          %MyApp.Course{id: index, title: "Course \#{index}", school_id: known.school.id, teacher_id: authorities.student.identity}
        end

        test "custom business rule still fits beside the generated matrix" do
          put_json_api_results(sample_models(3))
          conn = controller().update(conn_for(:principal), %{"id" => "3", "data" => %{}})
          assert conn.status in [200, 422]
        end
      end
  """

  alias Ecto.Adapters.SQL.Sandbox
  alias Hawk.Authority
  alias Hawk.MutationContext

  @doc """
  Declares the named `Hawk.Authority` values the generated matrix exercises.

  `:public` is always included automatically. The block receives the
  `pre_authorities/0` result and must return a map of `%{name => authority}`.
  """
  defmacro authorities(pre_authorities, do: block) do
    quote do
      def __hawk_authorities__(unquote(pre_authorities)), do: unquote(block)
    end
  end

  @doc """
  Declares shared context built once per test process (e.g. parent records),
  cached and threaded into `pre_sample/2` and `sample/4`.
  """
  defmacro pre_authorities(do: block) do
    quote do
      def __hawk_pre_authorities__, do: unquote(block)
    end
  end

  @doc """
  Builds shared context from `pre_authorities/0` and `authorities/0`, cached
  per test process. Useful when samples need shared parent records created via
  fixtures or factories.
  """
  defmacro pre_sample(pre_authorities, authorities, do: block) do
    quote do
      def pre_sample(unquote(pre_authorities), unquote(authorities)), do: unquote(block)
    end
  end

  @doc """
  Builds a deterministic resource sample for a given authority set, known
  context, and index. Required callback; the matrix uses generated samples for
  collection/pagination coverage and `sample_model/0` (index 1) for
  show/update/delete.
  """
  defmacro sample(pre_authorities, authorities, known, index, do: block) do
    quote do
      def sample(
            unquote(pre_authorities),
            unquote(authorities),
            unquote(known),
            unquote(index)
          ),
          do: unquote(block)
    end
  end

  @doc false
  def maybe_start_sandbox(repo, tags, on_exit_fun) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) do
      owner = Sandbox.start_owner!(repo, shared: not tags[:async])
      on_exit_fun.(fn -> Sandbox.stop_owner(owner) end)
    end
  end

  defmacro __using__(opts) do
    controller = Keyword.fetch!(opts, :controller)
    resource = Keyword.fetch!(opts, :resource)
    model = Keyword.fetch!(opts, :model)
    sample_count = Keyword.get(opts, :sample_count, 3)
    repo = Keyword.get(opts, :repo)
    create_params = Keyword.get(opts, :create_params)
    update_params = Keyword.get(opts, :update_params)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

      import Hawk.JsonApiControllerCase,
        only: [
          assert_json_api_controller_matrix: 1,
          assert_index_query_growth: 2,
          authorities: 2,
          count_repo_queries: 2,
          count_repo_queries: 3,
          n_plus_one_guard: 1,
          pre_authorities: 1,
          pre_sample: 3,
          sample: 5
        ]

      @hawk_json_api_controller_case %{
        controller: unquote(controller),
        resource: unquote(resource),
        model: unquote(model),
        repo: unquote(repo),
        sample_count: unquote(sample_count),
        create_params: unquote(create_params),
        update_params: unquote(update_params)
      }

      test "Hawk JSON:API controller role/action matrix" do
        assert_json_api_controller_matrix(__MODULE__)
      end

      if unquote(repo) do
        setup tags do
          Hawk.JsonApiControllerCase.maybe_start_sandbox(unquote(repo), tags, &on_exit/1)
          :ok
        end
      end

      def __hawk_json_api_controller_case__, do: @hawk_json_api_controller_case

      def controller, do: @hawk_json_api_controller_case.controller

      def __hawk_authorities__(_pre_authorities), do: %{}
      def __hawk_pre_authorities__, do: %{}
      def pre_sample(_pre_authorities, _authorities), do: %{}

      def pre_authorities, do: Hawk.JsonApiControllerCase.pre_authorities_context(__MODULE__)

      def sample(_pre_authorities, _authorities, _known, _index) do
        raise ArgumentError,
              "define sample(pre_authorities, authorities, known, index) in #{inspect(__MODULE__)} when using Hawk.JsonApiControllerCase; return one deterministic #{inspect(@hawk_json_api_controller_case.model)} sample for the given index"
      end

      def authorities, do: Hawk.JsonApiControllerCase.authority_map(__MODULE__)
      def sample_context, do: Hawk.JsonApiControllerCase.sample_context(__MODULE__)

      def generate_sample(index),
        do: Hawk.JsonApiControllerCase.generate_sample(__MODULE__, index)

      def generate_samples(count \\ @hawk_json_api_controller_case.sample_count),
        do: Hawk.JsonApiControllerCase.generate_samples(__MODULE__, count)

      def sample_model, do: generate_sample(1)

      def sample_models(count \\ @hawk_json_api_controller_case.sample_count),
        do: generate_samples(count)

      defoverridable __hawk_authorities__: 1,
                     __hawk_pre_authorities__: 0,
                     pre_sample: 2,
                     sample: 4

      def create_params, do: Hawk.JsonApiControllerCase.create_params_for(__MODULE__)
      def update_params, do: Hawk.JsonApiControllerCase.update_params_for(__MODULE__)

      def conn_for(name) when is_atom(name) do
        __MODULE__
        |> Hawk.JsonApiControllerCase.authority_cases()
        |> Enum.find(fn role_case -> role_case.name == name end)
        |> case do
          nil -> raise ArgumentError, "unknown authority case #{inspect(name)}"
          role_case -> conn_for(role_case.authority)
        end
      end

      def conn_for(%Hawk.Authority{} = authority) do
        Hawk.JsonApiControllerCase.conn_for(authority)
      end

      def put_json_api_results(results) when is_list(results) do
        Hawk.JsonApiControllerCase.put_json_api_results(@hawk_json_api_controller_case, results)
      end
    end
  end

  @doc """
  Generates a test that asserts index query growth stays bounded as the
  collection size grows, catching N+1 preloads.

  ## Options

    * `:include` — the `include` query param.
    * `:params` — extra query params.
    * `:parent_counts` — collection sizes to compare (default `[1, sample_count]`).
    * `:max_extra_queries` — allowed extra queries per parent added (default `0`).
  """
  defmacro n_plus_one_guard(opts) do
    description =
      opts
      |> Keyword.take([:include, :params, :parent_counts, :max_extra_queries])
      |> inspect()

    opts = Macro.escape(opts)

    quote do
      test "Hawk JSON:API index query growth stays bounded #{unquote(description)}" do
        assert_index_query_growth(__MODULE__, unquote(opts))
      end
    end
  end

  @doc false
  def assert_json_api_controller_matrix(test_module) do
    config = test_module.__hawk_json_api_controller_case__()
    samples = sample_models(test_module, config.sample_count)
    config = Map.merge(config, %{sample: List.first(samples), samples: samples})

    test_module
    |> authority_cases()
    |> Enum.each(fn role_case ->
      assert_index(config, role_case)
      assert_paginated_index(config, role_case)
      assert_show(config, role_case)
      assert_create(config, role_case)
      assert_update(config, role_case)
      assert_delete(config, role_case)
    end)
  end

  @doc false
  def assert_index_query_growth(test_module, opts) when is_atom(test_module) and is_list(opts) do
    config = test_module.__hawk_json_api_controller_case__()
    repo = config.repo || raise ArgumentError, "n_plus_one_guard requires :repo in Hawk.JsonApiControllerCase"

    unless ecto_repo?(repo) do
      raise ArgumentError, "n_plus_one_guard requires an Ecto repo, got #{inspect(repo)}"
    end

    parent_counts = Keyword.get(opts, :parent_counts, [1, max(config.sample_count, 2)])
    max_extra_queries = Keyword.get(opts, :max_extra_queries, 0)
    role_case = query_growth_role_case(test_module, config, Keyword.get(opts, :authority))

    results =
      Enum.map(parent_counts, fn parent_count ->
        samples = sample_models(test_module, parent_count)
        put_results(config, samples)

        params = query_growth_params(opts, parent_count)

        {conn, query_count} =
          count_repo_queries(repo, fn ->
            config.controller.index(conn_for(role_case.authority), params)
          end)

        assert_status(conn, 200, role_case, :n_plus_one_guard)
        %{parent_count: parent_count, query_count: query_count, params: params}
      end)

    baseline = hd(results)

    Enum.each(tl(results), fn result ->
      ExUnit.Assertions.assert(
        result.query_count <= baseline.query_count + max_extra_queries,
        """
        expected bounded Hawk JSON:API query growth for #{inspect(config.controller)} index

        baseline parent_count=#{baseline.parent_count}: #{baseline.query_count} queries
        parent_count=#{result.parent_count}: #{result.query_count} queries
        max_extra_queries=#{max_extra_queries}
        params=#{inspect(result.params)}
        """
      )
    end)

    results
  end

  @doc """
  Runs `fun` and returns `{result, query_count}` by attaching a telemetry
  handler to the repo's query event. Useful for ad-hoc query-count assertions.
  """
  def count_repo_queries(repo, fun, opts \\ []) when is_atom(repo) and is_function(fun, 0) do
    test_pid = self()
    ref = make_ref()
    handler_id = {__MODULE__, self(), ref}
    ignored_sources = Keyword.get(opts, :ignored_sources, ["schema_migrations"])

    :telemetry.attach(
      handler_id,
      repo_query_event(repo, opts),
      &__MODULE__.handle_query_event/4,
      %{test_pid: test_pid, ref: ref, ignored_sources: ignored_sources}
    )

    try do
      result = fun.()
      {result, drain_query_count(ref, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  @doc false
  def handle_query_event(_event, _measurements, metadata, %{
        test_pid: test_pid,
        ref: ref,
        ignored_sources: ignored_sources
      }) do
    unless metadata[:source] in ignored_sources do
      send(test_pid, {ref, :query})
    end
  end

  @doc false
  def create_params_for(test_module) do
    config = test_module.__hawk_json_api_controller_case__()

    case config.create_params do
      nil -> mutation_params(config.model, :creatable)
      params -> resolve_params(params)
    end
  end

  @doc false
  def update_params_for(test_module) do
    config = test_module.__hawk_json_api_controller_case__()

    case {config.update_params, config.create_params} do
      {nil, nil} -> mutation_params(config.model, :updatable)
      {nil, params} -> resolve_params(params)
      {params, _create_params} -> resolve_params(params)
    end
  end

  defp resolve_params(params) when is_function(params, 0), do: params.()
  defp resolve_params(params), do: params

  def sample_context(test_module) when is_atom(test_module) do
    key = {__MODULE__, test_module, :sample_context}

    case Process.get(key) do
      nil ->
        pre_auth = pre_authorities_context(test_module)
        known = test_module.pre_sample(pre_auth, authority_map(test_module))
        Process.put(key, known)
        known

      known ->
        known
    end
  end

  def generate_sample(test_module, index)
      when is_atom(test_module) and is_integer(index) and index > 0 do
    pre_auth = pre_authorities_context(test_module)
    test_module.sample(pre_auth, authority_map(test_module), sample_context(test_module), index)
  end

  def generate_samples(test_module, count) when is_integer(count) and count > 0 do
    Enum.map(1..count, &generate_sample(test_module, &1))
  end

  def sample_models(test_module, count) when is_integer(count) and count > 0 do
    generate_samples(test_module, count)
  end

  def conn_for(%Authority{} = authority) do
    Plug.Test.conn("get", "/")
    |> Plug.Conn.assign(:hawk_authority, authority)
  end

  def put_json_api_results(config, results) when is_list(results) do
    put_results(config, results)
  end

  defp assert_index(config, role_case) do
    put_results(config, if(read_allowed?(config, role_case), do: config.samples, else: []))

    conn = config.controller.index(conn_for(role_case.authority), %{})

    assert_status(conn, 200, role_case, :index)

    assert_index_size(
      config,
      conn,
      if(read_allowed?(config, role_case), do: length(config.samples), else: 0),
      role_case
    )
  end

  defp assert_paginated_index(config, role_case) do
    put_results(config, if(read_allowed?(config, role_case), do: config.samples, else: []))

    page_size = min(2, length(config.samples))

    conn =
      config.controller.index(conn_for(role_case.authority), %{
        "page" => %{"size" => to_string(page_size)}
      })

    assert_status(conn, 200, role_case, :paginated_index)
    assert_json_api_collection(conn, role_case, :paginated_index)
  end

  defp assert_show(config, role_case) do
    read? = read_allowed?(config, role_case)
    put_results(config, if(read?, do: [config.sample], else: []))

    conn =
      config.controller.show(conn_for(role_case.authority), %{"id" => model_id(config.sample)})

    assert_status(conn, if(read?, do: 200, else: 404), role_case, :show)
  end

  defp assert_create(config, role_case) do
    write? = write_allowed?(config, role_case, :create)

    conn =
      config.controller.create(
        conn_for(role_case.authority),
        resolve_params(config.create_params) || mutation_params(config.model, :creatable)
      )

    expected_status = if(write?, do: [201, 422], else: [403, 422])
    assert_status(conn, expected_status, role_case, :create)
  end

  defp assert_update(config, role_case) do
    read? = read_allowed?(config, role_case)
    write? = write_allowed?(config, role_case, :update)
    put_results(config, if(read?, do: [config.sample], else: []))

    params =
      config.update_params || config.create_params ||
        mutation_params(config.model, :updatable)

    id = model_id(config.sample)

    update_params =
      params
      |> resolve_params()
      |> Map.put("id", id)
      |> update_in(["data"], &Map.put(&1, "id", id))

    conn = config.controller.update(conn_for(role_case.authority), update_params)

    expected_status =
      cond do
        write? -> [200, 422]
        read? -> [403, 422]
        true -> 404
      end

    assert_status(conn, expected_status, role_case, :update)
  end

  defp assert_delete(config, role_case) do
    read? = read_allowed?(config, role_case)
    write? = write_allowed?(config, role_case, :delete)
    put_results(config, if(read?, do: [config.sample], else: []))

    conn =
      config.controller.delete(conn_for(role_case.authority), %{"id" => model_id(config.sample)})

    expected_status =
      cond do
        write? -> [204, 422]
        read? -> [403, 422]
        true -> 404
      end

    assert_status(conn, expected_status, role_case, :delete)
  end

  defp assert_json_api_collection(conn, role_case, action) do
    case decode(conn) do
      %{data: data} when is_list(data) ->
        :ok

      _other ->
        ExUnit.Assertions.flunk(
          "expected #{role_case.name} #{action} to return a JSON:API collection document, got #{inspect(decode(conn))}"
        )
    end
  end

  defp assert_index_size(%{repo: repo}, conn, expected, role_case) do
    if ecto_repo?(repo) do
      :ok
    else
      assert_index_size_for_static_repo(conn, expected, role_case)
    end
  end

  defp assert_index_size_for_static_repo(conn, expected, role_case) do
    case decode(conn) do
      %{data: data} when is_list(data) ->
        ExUnit.Assertions.assert(
          length(data) == expected,
          "expected #{role_case.name} index to return #{expected} resources, got #{length(data)}"
        )

      _other ->
        :ok
    end
  end

  defp assert_status(conn, expected, role_case, action) do
    ExUnit.Assertions.assert(
      conn.status in List.wrap(expected),
      "expected #{role_case.name} #{action} to return #{expected}, got #{inspect(conn.status)} with body #{inspect(safe_decode(conn))}"
    )
  end

  defp decode(%Plug.Conn{resp_body: body}) when is_binary(body) and byte_size(body) > 0,
    do: Jason.decode!(body, keys: :atoms)

  defp decode(_conn), do: nil

  defp safe_decode(%Plug.Conn{resp_body: body}) when is_binary(body) and byte_size(body) > 0,
    do: Jason.decode!(body, keys: :atoms)

  defp safe_decode(_conn), do: ""

  def authority_map(test_module) when is_atom(test_module) do
    test_module
    |> authority_cases()
    |> Map.new(fn %{name: name, authority: authority} -> {name, authority} end)
  end

  def authority_cases(test_module) when is_atom(test_module) do
    pre_auth = pre_authorities_context(test_module)

    test_module.__hawk_authorities__(pre_auth)
    |> normalize_authority_cases()
    |> include_public_authority()
  end

  def pre_authorities_context(test_module) when is_atom(test_module) do
    key = {__MODULE__, test_module, :pre_authorities_context}

    case Process.get(key) do
      nil ->
        known = test_module.__hawk_pre_authorities__()
        Process.put(key, known)
        known

      known ->
        known
    end
  end

  defp normalize_authority_cases(authorities) when is_map(authorities) do
    authorities
    |> Map.to_list()
    |> Enum.map(&normalize_authority_case/1)
  end

  defp normalize_authority_cases(authorities) when is_list(authorities) do
    Enum.map(authorities, &normalize_authority_case/1)
  end

  defp include_public_authority(cases) do
    if Enum.any?(cases, &(&1.name == :public)) do
      cases
    else
      cases ++ [%{name: :public, authority: Authority.public()}]
    end
  end

  defp query_growth_role_case(test_module, config, nil) do
    Enum.find(authority_cases(test_module), &read_allowed?(config, &1)) ||
      raise ArgumentError,
            "n_plus_one_guard could not find a readable authority case for #{inspect(test_module)}"
  end

  defp query_growth_role_case(test_module, _config, name) when is_atom(name) do
    Enum.find(authority_cases(test_module), &(&1.name == name)) ||
      raise ArgumentError,
            "n_plus_one_guard authority #{inspect(name)} is not defined for #{inspect(test_module)}"
  end

  defp query_growth_role_case(_test_module, _config, %Authority{} = authority) do
    %{name: :custom, authority: authority}
  end

  defp query_growth_params(opts, parent_count) do
    opts
    |> Keyword.get(:params, %{})
    |> stringify_keys()
    |> maybe_put_include(Keyword.get(opts, :include))
    |> put_page_size(parent_count)
  end

  defp maybe_put_include(params, nil), do: params
  defp maybe_put_include(params, include), do: Map.put(params, "include", include)

  defp put_page_size(params, parent_count) do
    Map.update(params, "page", %{"size" => to_string(parent_count)}, fn page ->
      page
      |> stringify_keys()
      |> Map.put("size", to_string(parent_count))
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)

  defp stringify_keys(value), do: value

  def normalize_authority_case({name, %Authority{} = authority}) when is_atom(name) do
    %{name: name, authority: authority}
  end

  def normalize_authority_case({name, opts}) when is_atom(name) and is_list(opts) do
    %{name: name, authority: Keyword.fetch!(opts, :authority)}
  end

  def normalize_authority_case(%{name: name, authority: %Authority{} = authority}) do
    %{name: name, authority: authority}
  end

  defp read_allowed?(config, role_case) do
    reader = config.resource.__hawk_resource__(:reader)
    reader.read_filter(role_case.authority) != :none
  end

  defp write_allowed?(config, role_case, action) do
    policy = config.resource.__hawk_resource__(:policy)
    context = mutation_context(action, config.sample, role_case.authority)

    if function_exported?(policy, predicate(action), 1) do
      apply(policy, predicate(action), [context]) in [true, :ok]
    else
      false
    end
  end

  defp mutation_context(:create, sample, authority),
    do: MutationContext.create(struct(sample.__struct__), %{}, authority)

  defp mutation_context(:update, sample, authority),
    do: MutationContext.update(sample, %{}, authority)

  defp mutation_context(:delete, sample, authority), do: MutationContext.delete(sample, authority)

  defp predicate(:create), do: :create?
  defp predicate(:update), do: :update?
  defp predicate(:delete), do: :delete?

  defp put_results(%{repo: nil}, _results), do: :ok

  defp put_results(%{repo: repo}, results) do
    if ecto_repo?(repo) do
      Enum.each(results, &insert_sample!(repo, &1))
    else
      Process.put({repo, :all_results}, results)
    end
  end

  defp ecto_repo?(repo) do
    Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0)
  end

  defp repo_query_event(repo, opts) do
    prefix =
      Keyword.get(opts, :telemetry_prefix) || repo.config()[:telemetry_prefix] ||
        raise ArgumentError,
              "could not determine telemetry_prefix for #{inspect(repo)}; pass :telemetry_prefix to count_repo_queries/3"

    prefix ++ [:query]
  end

  defp drain_query_count(ref, count) do
    receive do
      {^ref, :query} -> drain_query_count(ref, count + 1)
    after
      0 -> count
    end
  end

  defp insert_sample!(repo, sample) when is_struct(sample) do
    case repo.insert(sample, on_conflict: :nothing) do
      {:ok, _record} ->
        :ok

      {:error, changeset} ->
        ExUnit.Assertions.flunk("failed to insert JSON:API controller sample: #{inspect(changeset)}")
    end
  end

  defp model_id(model), do: model |> Map.fetch!(:id) |> to_string()

  def mutation_params(model, capability) do
    json_api = Hawk.JsonApi.Schema.metadata(model)
    allowed = Map.fetch!(json_api, capability)

    data = %{
      "type" => json_api.type,
      "attributes" => attribute_examples(json_api, allowed),
      "relationships" => relationship_examples(json_api, allowed)
    }

    data =
      if capability == :updatable do
        identity = Hawk.JsonApi.Schema.identity(model)
        Map.put(data, "id", model |> Map.fetch!(identity) |> to_string())
      else
        data
      end

    %{"data" => data}
  end

  defp attribute_examples(json_api, allowed) do
    json_api.attributes
    |> Map.take(allowed)
    |> Map.new(fn {name, metadata} ->
      {to_string(name), Map.get(metadata, :example, "example")}
    end)
  end

  defp relationship_examples(json_api, allowed) do
    json_api.relationships
    |> Map.take(allowed)
    |> Map.new(fn {name, metadata} ->
      {to_string(name), %{"data" => json_value(Map.fetch!(metadata, :example))}}
    end)
  end

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), json_value(nested)} end)
  end

  defp json_value(value), do: value
end
