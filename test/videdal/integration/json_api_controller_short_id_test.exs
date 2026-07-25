defmodule Videdal.Integration.JsonApiControllerShortIdTest.CourseReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.Course,
    policy: Videdal.Integration.JsonApiControllerShortIdTest.AllowAllPolicy

  filter(:id)
end

defmodule Videdal.Integration.JsonApiControllerShortIdTest.AllowAllPolicy do
  @moduledoc false

  def read_filter(_authority), do: :all
end

defmodule Videdal.Integration.JsonApiControllerShortIdTest.Courses do
  @moduledoc false

  alias Videdal.Integration.JsonApiControllerShortIdTest.CourseReader

  def one(opts), do: CourseReader.one(opts)
  def all(opts), do: CourseReader.all(opts)
end

defmodule Videdal.Integration.JsonApiControllerShortIdTest.CoursesController do
  @moduledoc false

  use Hawk.JsonApi.Controller,
    resource: Videdal.Integration.JsonApiControllerShortIdTest.Courses,
    model: Videdal.Course
end

defmodule Videdal.Integration.JsonApiControllerShortIdTest do
  use Videdal.DatabaseCase, async: false

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Videdal.{Course, SandboxRepo, School, Teacher}
  alias Videdal.Integration.JsonApiControllerShortIdTest.CoursesController

  @moduletag :database

  setup do
    Videdal.DatabaseCase.reset_schema!()
    :ok
  end

  test "show resolves a short id through a real PostgreSQL UUID range query" do
    course = seed_course(uuid("1234abcd", "1"))
    seed_course(uuid("8765abcd", "2"))
    short_id = course.id |> String.split("-") |> List.first()

    {conn, query_count} =
      count_queries(fn ->
        CoursesController.show(conn(Authority.system()), %{"id" => short_id})
      end)

    assert conn.status == 200
    assert resp(conn).data.id == course.id
    assert query_count == 1
  end

  defp uuid(prefix, suffix) do
    IO.iodata_to_binary([
      prefix,
      "-",
      "0000",
      "-",
      "0000",
      "-",
      "0000",
      "-",
      String.duplicate("0", 11),
      suffix
    ])
  end

  defp seed_course(id) do
    school = SandboxRepo.insert!(%School{name: "School #{id}"})
    teacher = SandboxRepo.insert!(%Teacher{name: "Teacher #{id}", school_id: school.id})

    SandboxRepo.insert!(%Course{
      id: id,
      title: "Course #{id}",
      school_id: school.id,
      teacher_id: teacher.id
    })
  end
end
