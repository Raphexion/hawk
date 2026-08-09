defmodule Videdal.Integration.CoordinateFilterTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Schools
end

defmodule Videdal.Integration.CoordinateFilterTest do
  use Videdal.DatabaseCase, async: false

  import Hawk.TestConn, only: [resp: 1]

  alias Hawk.Authority
  alias Hawk.Reader.FilterCompiler
  alias Videdal.Integration.CoordinateFilterTest.Controller
  alias Videdal.{Repo, School, Schools}

  @copenhagen %{lat: 55.6761, lng: 12.5683}

  setup do
    insert(:school, name: "Copenhagen", location: point(55.6761, 12.5683))
    insert(:school, name: "Roskilde", location: point(55.6415, 12.0803))
    insert(:school, name: "Aarhus", location: point(56.1629, 10.2039))
    insert(:school, name: "Unknown", location: nil)
    :ok
  end

  test "resource near filters use meters and exclude distant or missing locations" do
    results =
      Schools.all(
        authority: Authority.system(),
        filter: %{
          location: {:near, Map.put(@copenhagen, :radius_meters, 10_000)}
        }
      )

    assert Enum.map(results, & &1.name) == ["Copenhagen"]
  end

  test "JSON:API accepts nested near parameters" do
    request =
      Plug.Test.conn(
        :get,
        "/?filter%5Blocation%5D%5Bnear%5D%5Blat%5D=55.6761&" <>
          "filter%5Blocation%5D%5Bnear%5D%5Blng%5D=12.5683&" <>
          "filter%5Blocation%5D%5Bnear%5D%5Bradius_meters%5D=10000"
      )
      |> Plug.Conn.fetch_query_params()
      |> Plug.Conn.assign(:hawk_authority, Authority.system())

    response = Controller.index(request, request.query_params)

    assert response.status == 200
    assert response |> resp() |> Map.fetch!(:data) |> Enum.map(& &1.attributes.name) == ["Copenhagen"]
  end

  test "JSON:API returns bad requests for malformed or excessive near filters" do
    invalid_queries = [
      {"lat=91&lng=12.5683&radius_meters=10000", ~r/lat must be between -90 and 90/},
      {"lat=55.6761&lng=12.5683&radius_meters=0", ~r/radius_meters must be greater than 0/},
      {"lat=55.6761&lng=12.5683&radius_meters=100001", ~r/radius_meters must not exceed 100000/},
      {"lat=55.6761&radius_meters=10000", ~r/requires lat, lng, and radius_meters/},
      {"lat=55.6761&lng=12.5683&radius_meters=10000&unit=km", ~r/unknown near parameter "unit"/}
    ]

    for {near_query, detail} <- invalid_queries do
      query = encode_near_query(near_query)

      request =
        Plug.Test.conn(:get, "/?" <> query)
        |> Plug.Conn.fetch_query_params()
        |> Plug.Conn.assign(:hawk_authority, Authority.system())

      response = Controller.index(request, request.query_params)

      assert response.status == 400
      assert [error] = resp(response).errors
      assert error.detail =~ detail
    end
  end

  test "the generated query keeps the geography column indexable" do
    query =
      FilterCompiler.compile(
        School,
        School,
        %{
          location:
            {:near,
             %{
               lat: @copenhagen.lat,
               lng: @copenhagen.lng,
               radius_meters: 10_000
             }}
        },
        Schools.Reader.filter_handlers(),
        Schools.Reader.coordinate_filters()
      )

    {sql, params} = Ecto.Adapters.SQL.to_sql(:all, Repo, query)

    assert sql =~ ~s[ST_DWithin(s0."location", ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)]
    refute sql =~ ~s[s0."location"::geography]
    assert params == [12.5683, 55.6761, 10_000]

    Repo.query!("SET LOCAL enable_seqscan = off")
    plan = Repo.query!("EXPLAIN " <> sql, params).rows |> List.flatten() |> Enum.join("\n")

    assert plan =~ "schools_location_gist_index"
  end

  defp point(lat, lng), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp encode_near_query(query) do
    query
    |> URI.decode_query()
    |> Enum.map_join("&", fn {key, value} ->
      "filter%5Blocation%5D%5Bnear%5D%5B#{key}%5D=#{URI.encode_www_form(value)}"
    end)
  end
end
