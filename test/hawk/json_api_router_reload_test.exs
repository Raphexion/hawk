defmodule Hawk.JsonApiRouterReloadTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "policy edits recompile ordinary and alias routers in a running VM", %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "lib"))

    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule Reload.MixProject do
      use Mix.Project
      def project, do: [app: :hawk_router_reload, version: "0.1.0", prune_code_paths: false]
    end
    """)

    File.write!(Path.join(tmp_dir, "lib/resource.ex"), """
    defmodule Reload.Resource do
      def __hawk_resource__(:policy), do: Reload.Policy
      def __hawk_resource__(key), do: Videdal.CourseCatalog.__hawk_resource__(key)
    end

    defmodule Reload.Alias do
      def __hawk_alias__ do
        %{resource: Reload.Resource, adapter: Videdal.CourseCatalog.JsonApi}
      end
    end
    """)

    File.write!(Path.join(tmp_dir, "lib/router.ex"), """
    defmodule Reload.Router do
      use Phoenix.Router
      import Hawk.JsonApi.Router
      hawk_json_api(Reload.Resource, Videdal.Controllers.CourseCatalogController)
    end

    defmodule Reload.AliasRouter do
      use Phoenix.Router
      import Hawk.JsonApi.Router
      hawk_json_api_alias(Reload.Alias, Videdal.Controllers.CourseCatalogController)
    end
    """)

    File.write!(Path.join(tmp_dir, "check.exs"), ~S'''
    ExUnit.start(autorun: false)
    import ExUnit.Assertions
    Mix.start()

    Mix.Project.in_project(:hawk_router_reload, File.cwd!(), fn _ ->
      # Keep the same VM and only edit the policy, as in a Phoenix reload.
      for declaration <- ["write(roles: [:system])", "write(:never)", "write(roles: [:system])"] do
        File.write!("lib/policy.ex", """
        defmodule Reload.Policy do
          use Hawk.Policy
          read do
            role(:system, :all)
          end
          #{declaration}
        end
        """)

        Mix.Task.clear()
        Mix.Task.run("compile")

        expected = Hawk.JsonApi.Routes.routes(Reload.Resource)
        expected_methods = Enum.map(expected, & &1.method)
        writable? = declaration != "write(:never)"
        assert (:post in expected_methods) == writable?
        assert (:patch in expected_methods) == writable?
        assert (:delete in expected_methods) == writable?

        for router <- [Reload.Router, Reload.AliasRouter] do
          assert Enum.map(router.__routes__(), &{&1.verb, &1.path}) ==
                   Enum.map(expected, &{&1.method, &1.path})
        end

        spec = Hawk.OpenApi.spec([Reload.Resource], title: "Reload test")
        assert Map.has_key?(spec.paths["/course-catalog"], :post) == writable?
        assert Map.has_key?(spec.paths["/course-catalog/{id}"], :patch) == writable?
        assert Map.has_key?(spec.paths["/course-catalog/{id}"], :delete) == writable?
      end
    end)

    IO.puts("Policy reload checks passed")
    ''')

    # Run Mix in a separate VM so this temporary project cannot affect the
    # application's compiler state or other concurrently running tests.
    elixir = :elixir |> :code.lib_dir() |> Path.join("../../bin/elixir") |> Path.expand()
    code_paths = Enum.flat_map(:code.get_path(), &["-pa", Path.expand(List.to_string(&1))])

    {output, status} =
      System.cmd(elixir, code_paths ++ ["check.exs"],
        cd: tmp_dir,
        env: [{"MIX_ENV", "dev"}, {"MIX_BUILD_PATH", nil}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "Policy reload checks passed"
  end
end
