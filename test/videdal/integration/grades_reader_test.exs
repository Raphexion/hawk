defmodule Videdal.Integration.GradesReaderTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Grades
end

defmodule Videdal.Integration.GradesReaderTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Grade,
    policy: Videdal.Grades.Policy

  filter(:id)
  filter(:school_id)
  filter(:student_id)
  filter(:course_id)
  filter(:score)

  preload(:student)
  preload(:course)

  attach :student, when_filter: [:student_name, :parent_id] do
    join(query, :inner, [root: grade], student in assoc(grade, :student), as: :student)
  end

  attach :parent_student, when_filter: [:parent_id] do
    join(query, :inner, [student: student], parent_student in assoc(student, :parent_students), as: :parent_student)
  end

  attach :course, when_filter: [:course_title, :teacher_id] do
    join(query, :inner, [root: grade], course in assoc(grade, :course), as: :course)
  end

  filter :student_name do
    fn {:eq, student_name} -> dynamic([student: student], student.name == ^student_name) end
  end

  filter :parent_id do
    fn {:eq, parent_id} ->
      dynamic([parent_student: parent_student], parent_student.parent_id == ^parent_id)
    end
  end

  filter :course_title do
    fn {:eq, course_title} -> dynamic([course: course], course.title == ^course_title) end
  end

  filter :teacher_id do
    fn {:eq, teacher_id} -> dynamic([course: course], course.teacher_id == ^teacher_id) end
  end
end

defmodule Videdal.Integration.GradesReaderTest do
  use Videdal.DatabaseCase, async: false

  import Hawk.TestConn, only: [resp: 1]

  alias Hawk.Authority
  alias Videdal.{Course, Grade, Grades, Parent, ParentStudent, Repo, School, Student, Teacher}
  alias Videdal.Integration.GradesReaderTest.{Controller, Reader}

  setup do
    {:ok, seed_school()}
  end

  test "resource supports the declared integer filter operators" do
    authority = Authority.system()

    for {filter, expected} <- [
          {%{score: 10}, [10]},
          {%{score: {:neq, 10}}, [7, 12]},
          {%{score: {:gt, 10}}, [12]},
          {%{score: {:gte, 10}}, [10, 12]},
          {%{score: {:lt, 10}}, [7]},
          {%{score: {:lte, 10}}, [7, 10]},
          {%{score: {:in, [7, 12]}}, [7, 12]},
          {%{score: {:not_in, [10]}}, [7, 12]}
        ] do
      scores = Grades.all(authority: authority, filter: filter) |> Enum.map(& &1.score) |> Enum.sort()
      assert scores == expected
    end
  end

  test "JSON:API casts and applies the declared integer filter operators" do
    authority = Authority.system()

    for {query, expected} <- [
          {"filter%5Bscore%5D=10", [10]},
          {"filter%5Bscore%5D%5Bneq%5D=10", [7, 12]},
          {"filter%5Bscore%5D%5Bgt%5D=10", [12]},
          {"filter%5Bscore%5D%5Bgte%5D=10", [10, 12]},
          {"filter%5Bscore%5D%5Blt%5D=10", [7]},
          {"filter%5Bscore%5D%5Blte%5D=10", [7, 10]},
          {"filter%5Bscore%5D%5Bin%5D%5B%5D=7&filter%5Bscore%5D%5Bin%5D%5B%5D=12", [7, 12]},
          {"filter%5Bscore%5D%5Bnot_in%5D%5B%5D=10", [7, 12]}
        ] do
      request =
        Plug.Test.conn(:get, "/?" <> query)
        |> Plug.Conn.fetch_query_params()
        |> Plug.Conn.assign(:hawk_authority, authority)

      response = Controller.index(request, request.query_params)

      assert response.status == 200

      scores =
        response
        |> resp()
        |> Map.fetch!(:data)
        |> Enum.map(& &1.attributes.score)
        |> Enum.sort()

      assert scores == expected
    end
  end

  test "JSON:API rejects invalid integer operands and operators with a bad request" do
    for {query, detail} <- [
          {"filter%5Bscore%5D%5Bgt%5D=many", ~s(invalid integer filter value "many" for field :score)},
          {"filter%5Bscore%5D%5Bin%5D%5B%5D=7&filter%5Bscore%5D%5Bin%5D%5B%5D=many",
           ~s(invalid integer filter value "many" for field :score)},
          {"filter%5Bscore%5D%5Bilike%5D=1%25", "filter operator :ilike is not supported for integer field :score"}
        ] do
      request =
        Plug.Test.conn(:get, "/?" <> query)
        |> Plug.Conn.fetch_query_params()
        |> Plug.Conn.assign(:hawk_authority, Authority.system())

      response = Controller.index(request, request.query_params)

      assert response.status == 400
      assert [error] = resp(response).errors
      assert error.detail == detail
    end
  end

  test "teachers query all grades for their courses with batched preloads", data do
    authority =
      Authority.new(:teacher, data.teacher.id, scopes: %{school_id: data.school.id, teacher_id: data.teacher.id})

    {grades, query_count} =
      count_queries(fn ->
        Reader.all(authority: authority, preloads: [:student, :course])
      end)

    grades = Enum.sort_by(grades, & &1.score, :desc)

    assert Enum.map(grades, & &1.score) == [12, 10]
    assert Enum.map(grades, & &1.student.name) == ["Ada", "Grace"]
    assert Enum.map(grades, & &1.course.title) == ["Math", "Math"]
    assert query_count == 3
  end

  test "students can only query their own grades", data do
    authority =
      Authority.new(:student, data.ada.id, scopes: %{school_id: data.school.id, student_id: data.ada.id})

    grades =
      Reader.all(authority: authority)
      |> Enum.sort_by(& &1.score, :desc)

    assert [%Grade{score: 12}, %Grade{score: 7}] = grades
    assert Reader.all(authority: authority, filter: %{student_id: data.grace.id}) == []
  end

  test "parents query grades through linked students only", data do
    authority =
      Authority.new(:parent, data.parent.id, scopes: %{school_id: data.school.id, parent_id: data.parent.id})

    {grades, query_count} =
      count_queries(fn ->
        Reader.all(authority: authority, preloads: [:student, :course])
      end)

    grades = Enum.sort_by(grades, & &1.course.title)

    assert [
             %Grade{score: 12, student: %Student{name: "Ada"}, course: %Course{title: "Math"}},
             %Grade{score: 7, student: %Student{name: "Ada"}, course: %Course{title: "Physics"}}
           ] = grades

    assert query_count == 3
  end

  defp seed_school do
    school = Repo.insert!(%School{name: "Videdal Skole"})
    teacher = Repo.insert!(%Teacher{name: "Ms. Curie", school_id: school.id})
    other_teacher = Repo.insert!(%Teacher{name: "Mr. Feynman", school_id: school.id})

    ada = Repo.insert!(%Student{name: "Ada", school_id: school.id})
    grace = Repo.insert!(%Student{name: "Grace", school_id: school.id})

    math =
      Repo.insert!(%Course{title: "Math", school_id: school.id, teacher_id: teacher.id})

    physics =
      Repo.insert!(%Course{
        title: "Physics",
        school_id: school.id,
        teacher_id: other_teacher.id
      })

    parent = Repo.insert!(%Parent{name: "Ada Parent", school_id: school.id})

    Repo.insert!(%ParentStudent{
      school_id: school.id,
      parent_id: parent.id,
      student_id: ada.id
    })

    Repo.insert!(%Grade{
      score: 12,
      school_id: school.id,
      student_id: ada.id,
      course_id: math.id
    })

    Repo.insert!(%Grade{
      score: 10,
      school_id: school.id,
      student_id: grace.id,
      course_id: math.id
    })

    Repo.insert!(%Grade{
      score: 7,
      school_id: school.id,
      student_id: ada.id,
      course_id: physics.id
    })

    %{
      school: school,
      teacher: teacher,
      ada: ada,
      grace: grace,
      parent: parent
    }
  end
end
