defmodule Hawk.PaginationTest.CustomPolicy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.PaginationTest.CustomReader do
  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Hawk.PaginationTest.CustomPolicy,
    default_page_size: 3,
    max_page_size: 5

  sort(:id)
end

defmodule Hawk.PaginationTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Hawk.PaginationTest.CustomReader
  alias Videdal.Courses
  alias Videdal.Courses.Reader

  test "readers declare sortable fields" do
    assert Reader.sort_keys() == MapSet.new([:id, :title])
  end

  test "reader applies declared sorting, page number, and page size" do
    insert_list(3, :course)

    results = Courses.all(authority: Authority.system(), sort: [{:desc, :title}], page: %{number: 1, size: 2})

    assert length(results) == 2
  end

  test "reader applies the default page size when none is requested" do
    insert_list(3, :course)

    results = Courses.all(authority: Authority.system())

    assert length(results) == 3
  end

  test "reader rejects sort smuggled inside :page" do
    assert_raise ArgumentError, ~r/:page no longer carries :column/, fn ->
      Courses.all(authority: Authority.system(), page: %{column: :title, dir: :desc})
    end
  end

  test "reader can override default and max page size per resource" do
    insert_list(4, :course)

    results = CustomReader.all(authority: Authority.system())

    assert length(results) == 3

    assert_raise ArgumentError, ~r/page size 6 exceeds maximum 5/, fn ->
      CustomReader.all(authority: Authority.system(), page: %{size: 6})
    end
  end

  test "reader rejects undeclared sort columns" do
    assert_raise ArgumentError, ~r/unsupported sort column :teacher_id/, fn ->
      Courses.all(authority: Authority.system(), sort: [{:asc, :teacher_id}])
    end
  end

  test "reader rejects page sizes above the configured maximum" do
    assert_raise ArgumentError, ~r/page size 101 exceeds maximum 100/, fn ->
      Courses.all(authority: Authority.system(), page: %{size: 101})
    end
  end

  test "reader pages overfetch one row and expose an exact continuation cursor" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    for title <- ["Same", "Same", "Zebra"] do
      insert(:course, title: title, school_id: school.id, teacher_id: teacher.id)
    end

    first = Courses.page(authority: Authority.system(), sort: [asc: :title], page: %{size: 2})

    assert length(first.entries) == 2
    assert first.has_more?
    assert is_binary(first.next_cursor)

    assert_raise ArgumentError, ~r/invalid or stale/, fn ->
      Courses.page(
        authority: Authority.system(),
        sort: [asc: :title],
        page: %{size: 2, after: first.next_cursor <> "tampered"}
      )
    end

    second =
      Courses.page(
        authority: Authority.system(),
        sort: [asc: :title],
        page: %{size: 2, after: first.next_cursor}
      )

    assert Enum.map(first.entries, & &1.id) -- Enum.map(second.entries, & &1.id) == Enum.map(first.entries, & &1.id)
    assert Enum.map(second.entries, & &1.title) == ["Zebra"]
    refute second.has_more?
    assert second.next_cursor == nil
  end

  test "reader page reports no continuation at an exact page boundary" do
    insert_list(2, :course)

    result = Courses.page(authority: Authority.system(), page: %{size: 2})

    assert length(result.entries) == 2
    refute result.has_more?
  end

  test "JSON:API request options parse page and sort parameters" do
    assert Hawk.JsonApi.Request.request_options(%{
             "sort" => "-title",
             "page" => %{"number" => "2", "size" => "25", "total" => "true"},
             "include" => "teacher,grades"
           }) == [
             sort: [{:desc, :title}],
             preloads: [:teacher, :grades],
             page: %{number: 2, size: 25, total: true}
           ]
  end

  test "JSON:API request options parse a forward cursor" do
    assert Hawk.JsonApi.Request.request_options(%{"page" => %{"after" => "opaque", "size" => "2"}}) ==
             [page: %{after: "opaque", size: 2}]
  end

  test "reader rejects mixing offset and cursor pagination" do
    assert_raise ArgumentError, ~r/cannot be combined/, fn ->
      Courses.page(authority: Authority.system(), page: %{number: 2, size: 2, after: "opaque"})
    end
  end

  test "JSON:API request options reject invalid page total values" do
    assert_raise ArgumentError, ~r/page\[total\] must be a boolean/, fn ->
      Hawk.JsonApi.Request.request_options(%{"page" => %{"total" => "sometimes"}})
    end
  end

  test "JSON:API request options parse page_size alias" do
    assert Hawk.JsonApi.Request.request_options(%{"page_size" => "2"}) == [page: %{size: 2}]
  end

  test "reader counts the authorized, unpaginated result set" do
    insert_list(3, :course)

    results = Courses.all(authority: Authority.system(), page: %{number: 1, size: 2})
    total_count = Courses.count(authority: Authority.system(), page: %{number: 1, size: 2})

    assert length(results) == 2
    assert total_count == 3
  end

  test "JSON:API documents include pagination metadata for collection pages" do
    document =
      Hawk.JsonApi.Document.document([%Videdal.Course{id: 1, title: "Math"}], page: %{number: 2, size: 1})

    assert document.meta == %{page: %{number: 2, size: 1, count: 1}}
  end

  test "JSON:API documents include total count when requested by the controller" do
    document =
      Hawk.JsonApi.Document.document([%Videdal.Course{id: 1, title: "Math"}],
        page: %{number: 2, size: 1, total: true},
        total_count: 12
      )

    assert document.meta == %{page: %{number: 2, size: 1, count: 1, total_count: 12}}
  end
end
