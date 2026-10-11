defmodule Videdal.CourseGradeProjections.Queries do
  @moduledoc false
  import Ecto.Query

  def source(%{context: %{only_course_id: course_id}}) do
    source_base()
    |> where([course: row], row.id == ^course_id)
  end

  def source(_context), do: source_base()

  defp source_base do
    from(course in Videdal.Course,
      as: :course,
      left_join: grade in assoc(course, :grades),
      group_by: [course.id, course.school_id],
      select: %{
        id: course.id,
        course_id: course.id,
        school_id: course.school_id,
        grade_count: count(grade.id)
      }
    )
  end

  def invalid_source(_context) do
    from(course in Videdal.Course,
      select: %{school_id: course.school_id}
    )
  end
end

defmodule Videdal.CourseGradeProjections.InvalidReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.CourseGradeProjection,
    policy: Videdal.CourseGradeProjections.Policy,
    source_query: &Videdal.CourseGradeProjections.Queries.invalid_source/1

  filter(:school_id)
end

defmodule Videdal.CourseGradeProjections.WritablePolicy do
  @moduledoc false
  use Hawk.Policy

  read(:all)
  write(roles: [:teacher])
end

defmodule Videdal.CourseGradeProjections.WritableReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.CourseGradeProjection,
    policy: Videdal.CourseGradeProjections.WritablePolicy,
    source_query: &Videdal.CourseGradeProjections.Queries.source/1
end

defmodule Videdal.CourseGradeProjections.Policy do
  @moduledoc false
  use Hawk.Policy

  read do
    role(:system, :all)
    role(:teacher, scopes: [:school_id])
  end

  write(:never)
end

defmodule Videdal.CourseGradeProjections.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.CourseGradeProjection,
    policy: Videdal.CourseGradeProjections.Policy,
    source_query: &Videdal.CourseGradeProjections.Queries.source/1

  filter(:school_id)
  filter(:course_id)
  sort(:grade_count)
  preload(:grades, reader: Videdal.Grades.Reader)
end
