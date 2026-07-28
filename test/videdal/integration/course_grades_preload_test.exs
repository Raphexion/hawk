defmodule Videdal.Integration.CourseGradesPreloadTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Videdal.Courses.Policy

  filter(:id)
  filter(:school_id)
  filter(:teacher_id)

  preload(:grades)
end

defmodule Videdal.Integration.CourseGradesPreloadTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Videdal.{Course, Grade, Repo, School, Student, Teacher}
  alias Videdal.Integration.CourseGradesPreloadTest.Reader

  setup do
    
    {:ok, seed_school()}
  end

  test "student course preloads include only that student's grades without N+1", data do
    authority =
      Authority.new(:student, data.ada.id, scopes: %{school_id: data.school.id, student_id: data.ada.id})

    {courses, query_count} =
      count_queries(fn ->
        Reader.all(authority: authority, preloads: [:grades])
      end)

    courses = Enum.sort_by(courses, & &1.title)

    assert Enum.map(courses, & &1.title) == ["Math", "Physics"]

    assert [
             %Course{grades: [%Grade{score: 12}]},
             %Course{grades: [%Grade{score: 7}]}
           ] = courses

    assert query_count == 2
  end

  test "teacher course preloads include all grades for that teacher's courses", data do
    authority =
      Authority.new(:teacher, data.teacher.id, scopes: %{school_id: data.school.id, teacher_id: data.teacher.id})

    {courses, query_count} =
      count_queries(fn ->
        Reader.all(authority: authority, preloads: [:grades])
      end)

    assert [%Course{title: "Math", grades: [%Grade{score: 12}, %Grade{score: 10}]}] = courses
    assert query_count == 2
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
      ada: ada
    }
  end
end
