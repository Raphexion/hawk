defmodule Hawk.Reader.CoordinatesTest.Place do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "coordinate_places" do
    field(:location, Geo.PostGIS.Geometry)
  end
end

defmodule Hawk.Reader.CoordinatesTest.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.Reader.CoordinatesTest.Reader do
  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Hawk.Reader.CoordinatesTest.Place,
    policy: Hawk.Reader.CoordinatesTest.Policy

  filter(:location, type: :coordinates, max_radius_meters: 100_000)
end

defmodule Hawk.Reader.CoordinatesTest.Resource do
  def __hawk_resource__(:reader), do: Hawk.Reader.CoordinatesTest.Reader
  def __hawk_resource__(:policy), do: Hawk.Reader.CoordinatesTest.Policy
  def __hawk_resource__(:json_api), do: false
end

defmodule Hawk.Reader.CoordinatesTest.BadPlace do
  use Ecto.Schema

  schema "bad_coordinate_places" do
    field(:location, :map)
  end
end

defmodule Hawk.Reader.CoordinatesTest.BadReader do
  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Hawk.Reader.CoordinatesTest.BadPlace,
    policy: Hawk.Reader.CoordinatesTest.Policy

  filter(:location, type: :coordinates, max_radius_meters: 100_000)
end

defmodule Hawk.Reader.CoordinatesTest.BadResource do
  def __hawk_resource__(:reader), do: Hawk.Reader.CoordinatesTest.BadReader
  def __hawk_resource__(:policy), do: Hawk.Reader.CoordinatesTest.Policy
  def __hawk_resource__(:json_api), do: false
end

defmodule Hawk.Reader.CoordinatesTest do
  use ExUnit.Case, async: true

  alias Hawk.Reader.CoordinatesTest.{Place, Reader}
  alias Hawk.Reader.FilterCompiler

  test "coordinate filters expose their declared contract" do
    assert Reader.filter_keys() == MapSet.new([:location])

    assert Reader.coordinate_filters() == %{
             location: %{max_radius_meters: 100_000}
           }
  end

  test "coordinate declarations require a positive maximum radius" do
    unique = System.unique_integer([:positive])

    invalid_options = [
      {"type: :coordinates", ~r/requires a positive :max_radius_meters/},
      {"type: :coordinates, max_radius_meters: 0", ~r/requires a positive :max_radius_meters/},
      {"type: :coordinates, max_radius_meters: 100, max_radius_meters: 200",
       ~r/duplicate coordinate filter options \[:max_radius_meters\]/}
    ]

    for {{options, message}, offset} <- Enum.with_index(invalid_options) do
      module_id = unique + offset

      assert_raise ArgumentError, message, fn ->
        Code.compile_string("""
        defmodule Hawk.Reader.CoordinatesTest.Invalid#{module_id}Place do
          use Ecto.Schema
          schema "invalid_coordinate_places" do
            field(:location, Geo.PostGIS.Geometry)
          end
        end

        defmodule Hawk.Reader.CoordinatesTest.Invalid#{module_id}Reader do
          use Hawk.Reader.Resource,
            repo: Videdal.Repo,
            schema: Hawk.Reader.CoordinatesTest.Invalid#{module_id}Place,
            policy: Hawk.Reader.CoordinatesTest.Policy

          filter(:location, #{options})
        end
        """)
      end
    end
  end

  test "reader declarations reject duplicate filter keys" do
    unique = System.unique_integer([:positive])

    assert_raise ArgumentError, "duplicate reader filter :location", fn ->
      Code.compile_string("""
      defmodule Hawk.Reader.CoordinatesTest.Duplicate#{unique}Place do
        use Ecto.Schema
        schema "duplicate_coordinate_places" do
          field(:location, Geo.PostGIS.Geometry)
        end
      end

      defmodule Hawk.Reader.CoordinatesTest.Duplicate#{unique}Reader do
        use Hawk.Reader.Resource,
          repo: Videdal.Repo,
          schema: Hawk.Reader.CoordinatesTest.Duplicate#{unique}Place,
          policy: Hawk.Reader.CoordinatesTest.Policy

        filter(:location)
        filter(:location, type: :coordinates, max_radius_meters: 100_000)
      end
      """)
    end
  end

  test "the resource contract requires a Geo.PostGIS.Geometry schema field" do
    assert Hawk.ResourceContract.validate!(
             Hawk.Reader.CoordinatesTest.Resource,
             Hawk.Reader.CoordinatesTest.Place
           ) == :ok

    assert_raise ArgumentError,
                 "reader coordinate filters must be Geo.PostGIS.Geometry schema fields: :location",
                 fn ->
                   Hawk.ResourceContract.validate!(
                     Hawk.Reader.CoordinatesTest.BadResource,
                     Hawk.Reader.CoordinatesTest.BadPlace
                   )
                 end
  end

  test "near compiles to ST_DWithin over the uncast root field" do
    query =
      FilterCompiler.compile(
        Place,
        Place,
        %{
          location:
            {:near,
             %{
               lat: "55.6761",
               lng: "12.5683",
               radius_meters: "10000"
             }}
        },
        Reader.filter_handlers(),
        Reader.coordinate_filters()
      )

    inspected = inspect(query)

    assert inspected =~ "ST_DWithin"
    assert inspected =~ "ST_SetSRID(ST_MakePoint"
    assert inspected =~ "p0.location"
    refute inspected =~ "p0.location::geography"
    assert inspected =~ "^55.6761"
    assert inspected =~ "^12.5683"
    assert inspected =~ "^10000.0"
  end

  test "near accepts boundary coordinates and the declared maximum" do
    for params <- [
          %{lat: 90, lng: 180, radius_meters: 100_000},
          %{lat: -90, lng: -180, radius_meters: 100_000}
        ] do
      assert %Ecto.Query{} =
               FilterCompiler.compile(
                 Place,
                 Place,
                 %{location: {:near, params}},
                 Reader.filter_handlers(),
                 Reader.coordinate_filters()
               )
    end
  end

  test "near validates coordinate ranges and radius" do
    valid = %{lat: 55.6761, lng: 12.5683, radius_meters: 10_000}

    invalid = [
      {%{valid | lat: 91}, ~r/lat must be between -90 and 90/},
      {%{valid | lng: -181}, ~r/lng must be between -180 and 180/},
      {%{valid | radius_meters: 0}, ~r/radius_meters must be greater than 0/},
      {%{valid | radius_meters: 100_001}, ~r/radius_meters must not exceed 100000/},
      {%{valid | lat: "north"}, ~r/lat must be a number/},
      {Map.delete(valid, :lng), ~r/requires lat, lng, and radius_meters/},
      {Map.put(valid, :unit, "km"), ~r/unknown near parameter :unit/},
      {Map.put(valid, "lat", valid.lat), ~r/duplicate near parameter :lat/}
    ]

    for {params, message} <- invalid do
      assert_raise ArgumentError, message, fn ->
        FilterCompiler.compile(
          Place,
          Place,
          %{location: {:near, params}},
          Reader.filter_handlers(),
          Reader.coordinate_filters()
        )
      end
    end
  end

  test "coordinate filters reject operators other than near" do
    assert_raise ArgumentError,
                 "filter operator :eq is not supported for coordinate field :location",
                 fn ->
                   FilterCompiler.compile(
                     Place,
                     Place,
                     %{location: %{lat: 55.6761, lng: 12.5683}},
                     Reader.filter_handlers(),
                     Reader.coordinate_filters()
                   )
                 end
  end
end
