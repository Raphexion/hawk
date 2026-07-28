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

    results = Courses.all(authority: Authority.system(), page: %{column: :title, dir: :desc, number: 1, size: 2})

    assert length(results) == 2
  end

  test "reader applies the default page size when none is requested" do
    insert_list(3, :course)

    results = Courses.all(authority: Authority.system())

    assert length(results) == 3
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
      Courses.all(authority: Authority.system(), page: %{column: :teacher_id})
    end
  end

  test "reader rejects page sizes above the configured maximum" do
    assert_raise ArgumentError, ~r/page size 101 exceeds maximum 100/, fn ->
      Courses.all(authority: Authority.system(), page: %{size: 101})
    end
  end

  test "JSON:API request options parse page and sort parameters" do
    assert Hawk.JsonApi.Request.request_options(%{
             "sort" => "-title",
             "page" => %{"number" => "2", "size" => "25"},
             "include" => "teacher,grades"
           }) == [
             page: %{column: :title, dir: :desc, number: 2, size: 25},
             preloads: [:teacher, :grades]
           ]
  end

  test "JSON:API request options parse page_size alias" do
    assert Hawk.JsonApi.Request.request_options(%{"page_size" => "2"}) == [page: %{size: 2}]
  end

  test "JSON:API documents include pagination metadata for collection pages" do
    document =
      Hawk.JsonApi.Document.document([%Videdal.Course{id: 1, title: "Math"}], page: %{number: 2, size: 1})

    assert document.meta == %{page: %{number: 2, size: 1, count: 1}}
  end
end
