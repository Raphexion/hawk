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

        authorities do
          %{
            principal: Hawk.Authority.new(:principal, 1),
            student: Hawk.Authority.new(:student, 2, scopes: %{school_id: 7})
          }
        end

        pre_sample authorities do
          %{school: %MyApp.School{id: 7}, teacher: authorities.student}
        end

        sample authorities, known, index do
          %MyApp.Course{id: index, title: "Course \#{index}", school_id: known.school.id, teacher_id: authorities.student.identity}
        end

        test "custom business rule still fits beside the generated matrix" do
          put_json_api_results(sample_models(3))
          conn = controller().update(conn_for(:principal), %{"id" => "3", "data" => %{}})
          assert conn.status in [200, 422]
        end
      end
  """

  alias Hawk.Authority
  alias Hawk.MutationContext

  defmacro authorities(do: block) do
    quote do
      def __hawk_authorities__, do: unquote(block)
    end
  end

  defmacro pre_sample(authorities, do: block) do
    quote do
      def pre_sample(unquote(authorities)), do: unquote(block)
    end
  end

  defmacro sample(authorities, known, index, do: block) do
    quote do
      def sample(unquote(authorities), unquote(known), unquote(index)), do: unquote(block)
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
          authorities: 1,
          pre_sample: 2,
          sample: 4
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
          if Code.ensure_loaded?(unquote(repo)) and
               function_exported?(unquote(repo), :__adapter__, 0) do
            owner =
              Ecto.Adapters.SQL.Sandbox.start_owner!(unquote(repo), shared: not tags[:async])

            on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
          end

          :ok
        end
      end

      def __hawk_json_api_controller_case__, do: @hawk_json_api_controller_case

      def controller, do: @hawk_json_api_controller_case.controller

      def __hawk_authorities__, do: %{}
      def pre_sample(_authorities), do: %{}

      def sample(_authorities, _known, _index) do
        raise ArgumentError,
              "define sample(authorities, known, index) in #{inspect(__MODULE__)} when using Hawk.JsonApiControllerCase; return one deterministic #{inspect(@hawk_json_api_controller_case.model)} sample for the given index"
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

      defoverridable __hawk_authorities__: 0, pre_sample: 1, sample: 3

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

  def create_params_for(test_module) do
    config = test_module.__hawk_json_api_controller_case__()

    case config.create_params do
      nil -> mutation_params(config.model, :creatable)
      params -> params
    end
  end

  def update_params_for(test_module) do
    config = test_module.__hawk_json_api_controller_case__()

    case {config.update_params, config.create_params} do
      {nil, nil} -> mutation_params(config.model, :updatable)
      {nil, params} -> params
      {params, _create_params} -> params
    end
  end

  def sample_context(test_module) when is_atom(test_module) do
    key = {__MODULE__, test_module, :sample_context}

    case Process.get(key) do
      nil ->
        known = test_module.pre_sample(authority_map(test_module))
        Process.put(key, known)
        known

      known ->
        known
    end
  end

  def generate_sample(test_module, index)
      when is_atom(test_module) and is_integer(index) and index > 0 do
    test_module.sample(authority_map(test_module), sample_context(test_module), index)
  end

  def generate_samples(test_module, count) when is_integer(count) and count > 0 do
    Enum.map(1..count, &generate_sample(test_module, &1))
  end

  def sample_models(test_module, count) when is_integer(count) and count > 0 do
    generate_samples(test_module, count)
  end

  def conn_for(%Authority{} = authority) do
    %{assigns: %{authority: authority}, status: nil, resp_body: nil}
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
        config.create_params || mutation_params(config.model, :creatable)
      )

    expected_status = if(write?, do: [201, 422], else: [403, 422])
    assert_status(conn, expected_status, role_case, :create)
  end

  defp assert_update(config, role_case) do
    read? = read_allowed?(config, role_case)
    write? = write_allowed?(config, role_case, :update)
    put_results(config, if(read?, do: [config.sample], else: []))

    conn =
      config.controller.update(
        conn_for(role_case.authority),
        Map.put(
          config.update_params || config.create_params ||
            mutation_params(config.model, :updatable),
          "id",
          model_id(config.sample)
        )
      )

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
        write? -> [200, 422]
        read? -> [403, 422]
        true -> 404
      end

    assert_status(conn, expected_status, role_case, :delete)
  end

  defp assert_json_api_collection(%{resp_body: %{data: data}}, _role_case, _action)
       when is_list(data), do: :ok

  defp assert_json_api_collection(conn, role_case, action) do
    ExUnit.Assertions.flunk(
      "expected #{role_case.name} #{action} to return a JSON:API collection document, got #{inspect(conn.resp_body)}"
    )
  end

  defp assert_index_size(%{repo: repo}, conn, expected, role_case) do
    if ecto_repo?(repo) do
      :ok
    else
      assert_index_size_for_static_repo(conn, expected, role_case)
    end
  end

  defp assert_index_size_for_static_repo(%{resp_body: %{data: data}}, expected, role_case)
       when is_list(data) do
    ExUnit.Assertions.assert(
      length(data) == expected,
      "expected #{role_case.name} index to return #{expected} resources, got #{length(data)}"
    )
  end

  defp assert_index_size_for_static_repo(_conn, _expected, _role_case), do: :ok

  defp assert_status(conn, expected, role_case, action) do
    ExUnit.Assertions.assert(
      conn.status in List.wrap(expected),
      "expected #{role_case.name} #{action} to return #{expected}, got #{inspect(conn.status)} with body #{inspect(conn.resp_body)}"
    )
  end

  def authority_map(test_module) when is_atom(test_module) do
    test_module
    |> authority_cases()
    |> Map.new(fn %{name: name, authority: authority} -> {name, authority} end)
  end

  def authority_cases(test_module) when is_atom(test_module) do
    test_module.__hawk_authorities__()
    |> normalize_authority_cases()
    |> include_public_authority()
  end

  def authority_cases(config) when is_map(config) and is_map_key(config, :authorities) do
    config.authorities
    |> normalize_authority_cases()
    |> include_public_authority()
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
    reader = Module.concat(config.resource, Reader)
    reader.read_filter(role_case.authority) != :none
  end

  defp write_allowed?(config, role_case, action) do
    policy = Module.concat(config.resource, Policy)
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

  defp insert_sample!(repo, sample) when is_struct(sample) do
    case repo.insert(sample, on_conflict: :nothing) do
      {:ok, _record} ->
        :ok

      {:error, changeset} ->
        ExUnit.Assertions.flunk(
          "failed to insert JSON:API controller sample: #{inspect(changeset)}"
        )
    end
  end

  defp model_id(model), do: model |> Map.fetch!(:id) |> to_string()

  def mutation_params(model, capability) do
    json_api = model.__hawk_json_api__()
    allowed = Map.fetch!(json_api, capability)

    %{
      "data" => %{
        "type" => json_api.type,
        "attributes" => attribute_examples(json_api, allowed),
        "relationships" => relationship_examples(json_api, allowed)
      }
    }
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
