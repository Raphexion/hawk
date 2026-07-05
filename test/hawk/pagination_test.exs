defmodule Hawk.PaginationTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Courses
  alias Videdal.Courses.Reader

  test "readers declare sortable fields" do
    assert Reader.sort_keys() == MapSet.new([:id, :title])
  end

  test "reader applies declared sorting and page size" do
    Process.put({Videdal.Repo, :all_results}, [])

    assert Courses.all(
             authority: Authority.system(),
             page: %{column: :title, dir: :desc, size: 25}
           ) == []

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "order_by: [desc: c0.title]"
    assert inspected =~ "limit: ^25"
  end

  test "reader rejects undeclared sort columns" do
    assert_raise ArgumentError, ~r/unsupported sort column :teacher_id/, fn ->
      Courses.all(authority: Authority.system(), page: %{column: :teacher_id})
    end
  end

  test "JSON:API request options parse page and sort parameters" do
    assert Hawk.JsonApi.request_options(%{
             "sort" => "-title",
             "page" => %{"size" => "25"},
             "include" => "teacher,grades"
           }) == [page: %{column: :title, dir: :desc, size: 25}, preloads: [:teacher, :grades]]
  end

  test "OpenAPI operation includes sort and pagination parameters" do
    operation = Hawk.JsonApi.openapi_index_operation(Videdal.Course)

    assert %{name: "sort", schema: %{enum: ["id", "-id", "title", "-title"]}} in operation.parameters
    assert %{name: "page[size]", schema: %{type: "integer", minimum: 0}} in operation.parameters
  end
end
