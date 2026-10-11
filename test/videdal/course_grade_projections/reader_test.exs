defmodule Videdal.CourseGradeProjections.ReaderTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority

  alias Videdal.{
    Course,
    CourseGradeProjections.InvalidReader,
    CourseGradeProjections.Reader,
    CourseGradeProjections.WritableReader,
    Grade,
    Repo,
    School
  }

  test "reads typed structs and counts a projection without a backing table" do
    school = Repo.insert!(%School{name: "Projection school"})
    course = Repo.insert!(%Course{title: "Computed", school_id: school.id})
    Repo.insert!(%Grade{course_id: course.id, school_id: school.id, score: 9})

    authority = Authority.new(:teacher, 1, scopes: %{school_id: school.id})

    assert [%Videdal.CourseGradeProjection{course_id: course_id, grade_count: 1}] =
             Reader.all(authority: authority, filter: %{course_id: course.id})

    assert course_id == course.id
    assert Reader.count(authority: authority, filter: %{course_id: course.id}) == 1

    assert [%Videdal.CourseGradeProjection{id: contextual_id}] =
             Reader.all(
               authority: authority,
               context: %{only_course_id: course.id}
             )

    assert contextual_id == course.id

    assert {:ok, %Videdal.CourseGradeProjection{grade_count: 1}} =
             Reader.one(authority: authority, filter: %{course_id: course.id})

    assert :not_found = Reader.one(authority: authority, filter: %{course_id: Ecto.UUID.generate()})

    assert Reader.all(authority: authority, filter: %{school_id: Ecto.UUID.generate()}) == []
  end

  test "sorts and paginates projected fields with accurate counts, including empty pages" do
    school = Repo.insert!(%School{name: "Page school"})
    one = Repo.insert!(%Course{title: "One", school_id: school.id})
    two = Repo.insert!(%Course{title: "Two", school_id: school.id})
    Repo.insert!(%Grade{course_id: one.id, school_id: school.id, score: 7})
    Repo.insert!(%Grade{course_id: two.id, school_id: school.id, score: 7})
    Repo.insert!(%Grade{course_id: two.id, school_id: school.id, score: 8})
    authority = Authority.new(:teacher, 1, scopes: %{school_id: school.id})

    page =
      Reader.page(
        authority: authority,
        sort: [desc: :grade_count],
        page: %{size: 1, total: true},
        select: [:course_id, :grade_count]
      )

    assert [%Videdal.CourseGradeProjection{course_id: id, grade_count: 2}] = page.entries
    assert id == two.id
    assert page.total_count == 2

    next_page =
      Reader.page(
        authority: authority,
        sort: [desc: :grade_count],
        page: %{size: 1, after: page.next_cursor}
      )

    assert [%Videdal.CourseGradeProjection{course_id: next_id, grade_count: 1}] = next_page.entries
    assert next_id == one.id

    empty_page =
      Reader.page(
        authority: authority,
        page: %{size: 1, number: 8, total: true}
      )

    assert empty_page.entries == []
    assert empty_page.total_count == 2
  end

  test "preloads preserve the selected parent restriction and use the related reader" do
    school = Repo.insert!(%School{name: "Preload school"})
    one = Repo.insert!(%Course{title: "One", school_id: school.id})
    two = Repo.insert!(%Course{title: "Two", school_id: school.id})
    grade = Repo.insert!(%Grade{course_id: one.id, school_id: school.id, score: 7})
    Repo.insert!(%Grade{course_id: two.id, school_id: school.id, score: 8})

    assert [%Videdal.CourseGradeProjection{id: id, grades: [loaded_grade]}] =
             Reader.all(
               authority: Authority.system(),
               filter: %{course_id: one.id},
               preloads: [:grades]
             )

    assert id == one.id
    assert loaded_grade.id == grade.id
  end

  test "rejects a missing identity projection and a writable source resource" do
    authority = Authority.new(:teacher, 1, scopes: %{school_id: Ecto.UUID.generate()})

    assert_raise ArgumentError, ~r/missing required projection fields \[:id\]/, fn ->
      InvalidReader.all(authority: authority)
    end

    assert_raise ArgumentError, ~r/requires an explicit write\(:never\) policy/, fn ->
      WritableReader.all(authority: authority)
    end
  end
end
