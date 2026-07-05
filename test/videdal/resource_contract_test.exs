defmodule Videdal.CourseGradeSummariesContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.CourseGradeSummaries,
    model: Videdal.CourseGradeSummary
end

defmodule Videdal.CoursesContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Videdal.EnrollmentsContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.Enrollments,
    model: Videdal.Enrollment
end

defmodule Videdal.GradesContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.Grades,
    model: Videdal.Grade
end

defmodule Videdal.ParentsContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.Parents,
    model: Videdal.Parent
end

defmodule Videdal.SchoolsContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.Schools,
    model: Videdal.School
end

defmodule Videdal.StudentsContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.Students,
    model: Videdal.Student
end

defmodule Videdal.TeachersContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.Teachers,
    model: Videdal.Teacher
end

defmodule Videdal.ParentStudentContractTest do
  use ExUnit.Case, async: true

  test "Hawk model declarations are consistent" do
    assert Videdal.ParentStudent.__hawk_resource__() == Videdal.ParentStudents
    assert :ok = contract_result(Videdal.ParentStudent)
  end

  defp contract_result(model) do
    Hawk.ResourceContract.validate_model!(model)
    :ok
  end
end
