defmodule Hawk.JsonApi.RequestTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Request

  test "request options parse JSON:API filter params" do
    assert Request.request_options(%{
             "filter" => %{
               "school_id" => "school-1",
               "active" => %{"eq" => "true"},
               "name" => %{"ilike" => "%math%"}
             }
           }) == [filter: %{school_id: "school-1", active: {:eq, true}, name: {:ilike, "%math%"}}]
  end

  test "sparse fieldsets parse JSON:API fields params without atomizing field names" do
    assert Request.sparse_fieldsets(%{"fields" => %{"courses" => "title,teacher", "schools" => "name"}}) == %{
             "courses" => MapSet.new(["title", "teacher"]),
             "schools" => MapSet.new(["name"])
           }
  end

  test "sparse fieldsets trim whitespace and keep empty fieldsets empty" do
    assert Request.sparse_fieldsets(%{"fields" => %{"courses" => " title, teacher, ", "schools" => ""}}) == %{
             "courses" => MapSet.new(["title", "teacher"]),
             "schools" => MapSet.new()
           }
  end

  test "request options preserve structured coordinate near filters" do
    assert Request.request_options(%{
             "filter" => %{
               "location" => %{
                 "near" => %{
                   "lat" => "55.6761",
                   "lng" => "12.5683",
                   "radius_meters" => "10000"
                 }
               }
             }
           }) == [
             filter: %{
               location:
                 {:near,
                  %{
                    "lat" => "55.6761",
                    "lng" => "12.5683",
                    "radius_meters" => "10000"
                  }}
             }
           ]
  end

  test "request options reject near on direct and custom fields without a coordinate declaration" do
    for {key, reader} <- [
          {:name, Videdal.Schools.Reader},
          {:school_name, Videdal.Courses.Reader}
        ] do
      assert_raise ArgumentError,
                   "filter operator near requires a declared coordinate filter for #{inspect(key)}",
                   fn ->
                     Request.request_options(
                       %{
                         "filter" => %{
                           to_string(key) => %{
                             "near" => %{
                               "lat" => "55.6761",
                               "lng" => "12.5683",
                               "radius_meters" => "10000"
                             }
                           }
                         }
                       },
                       reader: reader
                     )
                   end
    end
  end

  test "request options require an object for coordinate near filters" do
    assert_raise ArgumentError, "filter operator near requires an object", fn ->
      Request.request_options(%{
        "filter" => %{"location" => %{"near" => "55.6761,12.5683"}}
      })
    end
  end

  test "request options reject unsupported filter operators" do
    assert_raise ArgumentError, ~r/unsupported filter operator "starts_with"/, fn ->
      Request.request_options(%{"filter" => %{"name" => %{"starts_with" => "math"}}})
    end
  end

  test "attribute extraction supports nil relationships and ignores undeclared ones" do
    attrs =
      Request.attributes(
        %{
          "data" => %{
            "type" => "courses",
            "attributes" => %{"title" => "Math"},
            "relationships" => %{
              "school" => %{"data" => nil},
              "teacher" => %{"data" => %{"type" => "teachers", "id" => Videdal.teacher_id()}},
              "grades" => %{"data" => [%{"type" => "grades", "id" => Videdal.grade_id()}]}
            }
          }
        },
        Videdal.Course,
        :creatable
      )

    assert attrs == %{title: "Math", school_id: nil, teacher_id: Videdal.teacher_id()}
  end

  test "hostile attribute and relationship names are ignored without creating atoms" do
    hostile_attribute = hostile_name("attribute")
    hostile_relationship = hostile_name("relationship")

    attrs =
      Request.attributes(
        %{
          "data" => %{
            "type" => "courses",
            "attributes" => %{"title" => "Math", hostile_attribute => "boom"},
            "relationships" => %{
              "school" => %{"data" => nil},
              hostile_relationship => %{
                "data" => %{"type" => "schools", "id" => Videdal.school_id()}
              }
            }
          }
        },
        Videdal.Course,
        :creatable
      )

    assert attrs == %{title: "Math", school_id: nil}
    refute_existing_atom(hostile_attribute)
    refute_existing_atom(hostile_relationship)
  end

  test "short id filters use an indexed UUID range" do
    lower =
      IO.iodata_to_binary([
        "1234abcd",
        "-",
        "0000",
        "-",
        "0000",
        "-",
        "0000",
        "-",
        String.duplicate("0", 12)
      ])

    upper =
      IO.iodata_to_binary([
        "1234abcd",
        "-",
        "ffff",
        "-",
        "ffff",
        "-",
        "ffff",
        "-",
        "ffffffffffff"
      ])

    assert Request.short_id_filter("1234abcd") ==
             {:and, %{id: {:gte, lower}}, %{id: {:lte, upper}}}
  end

  test "hostile include and sort params are rejected without creating atoms" do
    hostile_include = hostile_name("include")
    hostile_sort = hostile_name("sort")

    assert_raise ArgumentError, ~r/unknown include/, fn ->
      Request.request_options(%{"include" => hostile_include})
    end

    assert_raise ArgumentError, ~r/unknown sort column/, fn ->
      Request.request_options(%{"sort" => hostile_sort})
    end

    refute_existing_atom(hostile_include)
    refute_existing_atom(hostile_sort)
  end

  test "request options preserve ordered comma-separated sort fields" do
    assert Request.request_options(%{"sort" => "title,-id"}) == [sort: [asc: :title, desc: :id]]
  end

  test "request options parse includes through reader preload declarations" do
    assert Request.request_options(
             %{"include" => "grades.student,teacher"},
             reader: Videdal.Courses.Reader
           ) == [preloads: [{:grades, [:student]}, :teacher]]
  end

  defp hostile_name(label), do: "hawk_hostile_#{label}_#{System.unique_integer([:positive])}"

  defp refute_existing_atom(name) do
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end
end
