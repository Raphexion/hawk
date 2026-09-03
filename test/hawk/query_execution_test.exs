defmodule Hawk.QueryExecutionTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority

  test "denied query policy prevents parameter casting" do
    assert {:error, error} =
             Videdal.SimilarCourses.page(
               authority: Authority.new(:student, "student-1"),
               params: %{"raise" => true}
             )

    assert error.status == 403
    assert error.code == :not_authorized
  end

  test "query policy narrows the source reader authorized root" do
    school = insert(:school)
    other_school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    other_teacher = insert(:teacher, school_id: other_school.id)
    visible = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Visible")

    _hidden =
      insert(:course, school_id: other_school.id, teacher_id: other_teacher.id, title: "Hidden")

    authority = Authority.new(:school_admin, "admin", scopes: %{school_id: school.id})

    page = Videdal.SimilarCourses.page(authority: authority, page: %{size: 10})

    assert Enum.map(page.entries, & &1.id) == [visible.id]
  end

  test "a broader query policy does not broaden the source resource policy" do
    school = insert(:school)
    other_school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    other_teacher = insert(:teacher, school_id: other_school.id)
    visible = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Visible")

    _hidden =
      insert(:course, school_id: other_school.id, teacher_id: other_teacher.id, title: "Hidden")

    authority = Authority.new(:school_admin, "admin", scopes: %{school_id: school.id})

    page =
      Hawk.QueryTest.OpenSimilarCourses.page(
        authority: authority,
        page: %{size: 10}
      )

    assert Enum.map(page.entries, & &1.id) == [visible.id]
  end

  test "declared ranking is deterministic through identity tie breaker" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course_b = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "B")
    course_a = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "A")

    page = Videdal.SimilarCourses.page(authority: Authority.public(), page: %{size: 10})

    assert Enum.map(page.entries, & &1.id) == [course_a.id, course_b.id]
  end

  test "required query params map to source reader filters" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    source = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Source")
    candidate = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Candidate")

    page =
      Hawk.QueryTest.ParamSimilarCourses.page(
        authority: Authority.public(),
        params: %{"source_course_id" => source.id},
        page: %{size: 10}
      )

    assert Enum.map(page.entries, & &1.id) == [candidate.id]
  end

  test "missing required query params return a safe JSON:API error" do
    assert {:error, error} =
             Hawk.QueryTest.ParamSimilarCourses.page(
               authority: Authority.public(),
               page: %{size: 10}
             )

    assert error.status == 400
    assert error.detail == "missing required query parameter source_course_id"
  end

  test "caller filters compose with parameter-derived source filters" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    source = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Source")
    visible = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Visible")
    _filtered = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Filtered")

    page =
      Hawk.QueryTest.ParamSimilarCourses.page(
        authority: Authority.public(),
        params: %{"source_course_id" => source.id},
        filter: %{title: "Visible"},
        page: %{size: 10}
      )

    assert Enum.map(page.entries, & &1.id) == [visible.id]
  end

  test "caller filters compose through declared query filters" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    visible = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Visible")
    _filtered = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Filtered")

    page =
      Videdal.SimilarCourses.page(
        authority: Authority.public(),
        filter: %{title: "Visible"},
        page: %{size: 10}
      )

    assert Enum.map(page.entries, & &1.id) == [visible.id]
  end

  test "caller cannot pass source reader options that are not part of the query contract" do
    assert_raise ArgumentError, ~r/unknown query option :sort/, fn ->
      Videdal.SimilarCourses.page(authority: Authority.public(), sort: [desc: :title])
    end
  end

  test "undeclared caller query filters are rejected before reaching the source reader" do
    assert_raise ArgumentError, ~r/unknown query filter key :teacher_id/, fn ->
      Videdal.SimilarCourses.page(
        authority: Authority.public(),
        filter: %{teacher_id: Ecto.UUID.generate()}
      )
    end
  end

  test "transactional prepare runs before source page execution" do
    course = insert(:course, title: "A")

    page =
      Videdal.SimilarCourses.page(
        authority: Authority.public(),
        context: %{test_pid: self()},
        params: %{"notify_prepare" => "true"},
        page: %{size: 10}
      )

    assert_received {:prepared, Videdal.Repo}
    assert Enum.map(page.entries, & &1.id) == [course.id]
  end

  test "transactional prepare and page query use the same transaction-local connection" do
    visible = insert(:course, title: "A")

    page =
      Videdal.PreparedSimilarCourses.page(
        authority: Authority.public(),
        params: %{"set_marker" => "ready"},
        filter: %{prepared_marker: "ready"},
        page: %{size: 10}
      )

    assert Enum.map(page.entries, & &1.id) == [visible.id]
  end

  test "ordinary source resource reads do not run query preparation" do
    course = insert(:course, title: "A")

    page = Videdal.Courses.page(authority: Authority.public(), context: %{test_pid: self()}, page: %{size: 10})

    refute_received {:prepared, Videdal.Repo}
    assert Enum.map(page.entries, & &1.id) == [course.id]
  end

  test "transactional prepare can stop execution with a safe error" do
    insert(:course, title: "A")

    assert {:error, error} =
             Videdal.SimilarCourses.page(
               authority: Authority.public(),
               params: %{"fail_prepare" => "true"},
               page: %{size: 10}
             )

    assert error.status == 400
    assert error.detail == "prepare failed"
  end

  test "rendering a query page performs no database queries after execution returns" do
    course = insert(:course, title: "A")
    page = Videdal.SimilarCourses.page(authority: Authority.public(), page: %{size: 10})

    {document, query_count} =
      count_queries(fn ->
        Hawk.JsonApi.Document.document(page.entries,
          authority: Authority.public(),
          page: page.page,
          has_more: page.has_more?,
          next_cursor: page.next_cursor
        )
      end)

    assert query_count == 0
    assert [%{id: id}] = document.data
    assert id == course.id
  end

  test "offset-only query declarations reject cursor pagination explicitly" do
    assert_raise ArgumentError,
                 ~r/Hawk query :similar_courses supports offset pagination only/,
                 fn ->
                   Videdal.SimilarCourses.page(
                     authority: Authority.public(),
                     page: %{after: "cursor"}
                   )
                 end
  end
end

defmodule Hawk.QueryTest.ParamSimilarCourses.Policy do
  use Hawk.Policy

  read(:all)
end

defmodule Hawk.QueryTest.ParamSimilarCourses do
  use Hawk.Query,
    name: :param_similar_courses,
    source: Videdal.Courses,
    pagination: :offset

  query_param(:source_course_id, required: true, source_filter: :similar_to_course_id)
  filter(:title)

  rank(:title_similarity, sort: [asc: :title], tie_breaker: :id)
end

defmodule Hawk.QueryTest.OpenSimilarCourses.Policy do
  use Hawk.Policy

  read(:all)
end

defmodule Hawk.QueryTest.OpenSimilarCourses do
  use Hawk.Query,
    name: :open_similar_courses,
    source: Videdal.Courses,
    pagination: :offset

  filter(:title)
end
