defmodule Videdal.Integration.JsonApiControllerShortIdTest.CourseReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.Course,
    policy: Videdal.Integration.JsonApiControllerShortIdTest.Courses.Policy

  filter(:id)
end

defmodule Videdal.Integration.JsonApiControllerShortIdTest.Courses.Policy do
  @moduledoc false

  use Hawk.Policy

  read(:all)
  write(:never)
end

defmodule Videdal.Integration.JsonApiControllerShortIdTest.Courses.Writer do
  @moduledoc false

  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.SandboxRepo,
    policy: Videdal.Integration.JsonApiControllerShortIdTest.Courses.Policy

  create do
    cast([:title, :school_id, :teacher_id])
  end

  update do
    cast([:title, :school_id, :teacher_id])
  end

  def delete(%Videdal.Course{} = course, authority) do
    Hawk.MutationContext.delete(course, authority)
    |> Hawk.MutationContext.validate_policy(&Videdal.Integration.JsonApiControllerShortIdTest.Courses.Policy.delete?/1)
    |> Hawk.RepositoryBoundary.delete(Videdal.SandboxRepo)
  end
end

defmodule Videdal.Integration.JsonApiControllerShortIdTest.Courses do
  @moduledoc false

  use Hawk.Resource,
    model: Videdal.Course,
    reader: Videdal.Integration.JsonApiControllerShortIdTest.CourseReader,
    json_api: Videdal.Courses.JsonApi,
    live_view: false
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
