defmodule Mix.Tasks.Hawk.ValidateTest do
  use ExUnit.Case, async: false

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn -> Mix.shell(previous_shell) end)

    :ok
  end

  defp capture_shell(fun) do
    fun.()
    receive_loop([])
  end

  defp receive_loop(acc) do
    receive do
      {:mix_shell, :info, msg} -> receive_loop([msg | acc])
      {:mix_shell, :error, msg} -> receive_loop([msg | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  test "validates all discovered Hawk resources and queries and passes" do
    output = capture_shell(fn -> Mix.Tasks.Hawk.Validate.run([]) end)

    assert output =~ "Hawk validation passed"
    assert output =~ "resource(s)"
    assert output =~ "query(ies)"
  end

  test "validates explicit resources" do
    output = capture_shell(fn -> Mix.Tasks.Hawk.Validate.run(["Videdal.Courses"]) end)

    assert output =~ "Hawk validation passed for 1 resource(s) and 0 query(ies)."
  end

  test "validates explicit queries" do
    output = capture_shell(fn -> Mix.Tasks.Hawk.Validate.run(["Videdal.SimilarCourses"]) end)

    assert output =~ "Hawk validation passed for 0 resource(s) and 1 query(ies)."
  end

  test "fails for a non-Hawk module" do
    assert_raise Mix.Error, ~r/Hawk validation failed/, fn ->
      capture_shell(fn -> Mix.Tasks.Hawk.Validate.run(["Videdal.Course"]) end)
    end
  end

  test "reports a clear error for a missing facade" do
    assert_raise Mix.Error, ~r/Hawk validation failed/, fn ->
      output = capture_shell(fn -> Mix.Tasks.Hawk.Validate.run(["NonExistent.Module"]) end)
      assert output =~ "is not a Hawk.Resource facade or Hawk.Query declaration"
    end
  end
end
