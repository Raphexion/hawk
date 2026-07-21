defmodule Mix.Tasks.Hawk.Gen.ResourceTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Hawk.Gen.Resource

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    tmp = Path.join(System.tmp_dir!(), "hawk-gen-resource-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    on_exit(fn ->
      Mix.shell(previous_shell)
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "generates a read-only resource skeleton", %{tmp: tmp} do
    File.cd!(tmp, fn ->
      Resource.run([
        "MyApp.Students",
        "MyApp.Student",
        "--repo",
        "MyApp.Repo",
        "--attributes",
        "name,grade_level",
        "--relationships",
        "school,parents",
        "--filters",
        "school_id,grade_level",
        "--preloads",
        "school,parents",
        "--read-only"
      ])
    end)

    assert_file(tmp, "lib/my_app/students.ex", "use Hawk.Resource")
    assert_file(tmp, "lib/my_app/students.ex", "model: MyApp.Student,")
    assert_file(tmp, "lib/my_app/students.ex", "writer: false")

    assert_file(tmp, "lib/my_app/students/reader.ex", "repo: MyApp.Repo,")
    assert_file(tmp, "lib/my_app/students/reader.ex", "schema: MyApp.Student")
    assert_file(tmp, "lib/my_app/students/reader.ex", "filter(:school_id)")
    assert_file(tmp, "lib/my_app/students/reader.ex", "preload(:parents)")

    assert_file(tmp, "lib/my_app/students/json_api.ex", "type(\"students\")")
    assert_file(tmp, "lib/my_app/students/json_api.ex", "attribute(:name")
    assert_file(tmp, "lib/my_app/students/json_api.ex", "relationship(:parents")

    assert_file(tmp, "lib/my_app/students/live_view.ex", "as(:student)")
    assert_file(tmp, "lib/my_app/students/live_view.ex", "plural_as(:students)")
    assert_file(tmp, "lib/my_app/students/live_view.ex", "column(:grade_level")
  end

  test "generates writer skeleton by default", %{tmp: tmp} do
    File.cd!(tmp, fn ->
      Resource.run([
        "MyApp.Courses",
        "MyApp.Course",
        "--repo",
        "MyApp.Repo",
        "--attributes",
        "title,code",
        "--relationships",
        "school,teacher"
      ])
    end)

    assert_file(tmp, "lib/my_app/courses.ex", "model: MyApp.Course")
    refute File.read!(Path.join(tmp, "lib/my_app/courses.ex")) =~ "writer: false"
    assert_file(tmp, "lib/my_app/courses/writer.ex", "use Hawk.Writer.Resource")

    assert_file(
      tmp,
      "lib/my_app/courses/writer.ex",
      "cast([:title, :code, :school_id, :teacher_id])"
    )

    assert_file(tmp, "lib/my_app/courses/writer.ex", "delete(:default)")

    assert_file(tmp, "lib/my_app/courses/json_api.ex", "relationship(:teacher, writable: true")
  end

  defp assert_file(root, path, expected) do
    full_path = Path.join(root, path)
    assert File.exists?(full_path), "expected #{path} to exist"
    assert File.read!(full_path) =~ expected
  end
end
