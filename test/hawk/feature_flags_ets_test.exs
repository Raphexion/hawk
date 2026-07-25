defmodule Hawk.FeatureFlagsEtsTest do
  @moduledoc """
  Pathfinder: a non-Ecto (ETS-backed) model served through Hawk's JSON:API
  machinery. Proves that `Hawk.Schema` is enough to back a flat read-only
  resource without an Ecto schema, repo, or database.
  """

  use ExUnit.Case, async: false

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Videdal.Controllers.FeatureFlagsController, as: Controller
  alias Videdal.FeatureFlag

  @system Authority.system()
  @table :feature_flags

  # A valid UUID kept out of the Videdal canonical id set.
  @flag_id "f0f0f0f0-f0f0-f0f0-f0f0-000000000001"
  @unknown_id "f0f0f0f0-f0f0-f0f0-f0f0-000000000099"

  setup do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table)
    end

    :ets.new(@table, [:set, :public, :named_table])

    :ets.insert(@table, {
      @flag_id,
      %FeatureFlag{
        id: @flag_id,
        key: "new_dashboard",
        enabled: true,
        description: "Toggle the new dashboard UI"
      }
    })

    :ok
  end

  test "index renders all flags from ETS with the adapter type" do
    conn = Controller.index(conn(@system), %{})

    assert conn.status == 200

    [flag] = resp(conn).data
    assert flag.id == @flag_id
    assert flag.type == "feature_flags"
    assert flag.attributes.key == "new_dashboard"
    assert flag.attributes.enabled == true
    assert flag.attributes.description == "Toggle the new dashboard UI"
  end

  test "show renders a single flag by id from ETS" do
    conn = Controller.show(conn(@system), %{"id" => @flag_id})

    assert conn.status == 200
    assert resp(conn).data.id == @flag_id
    assert resp(conn).data.type == "feature_flags"
    assert resp(conn).data.attributes.enabled == true
  end

  test "show returns 404 for an unknown id" do
    conn = Controller.show(conn(@system), %{"id" => @unknown_id})

    assert conn.status == 404
    assert [%{code: "not_found"}] = resp(conn).errors
  end

  test "index rejects malformed ids before touching ETS" do
    conn = Controller.show(conn(@system), %{"id" => "not-a-uuid"})

    assert conn.status == 400
  end
end
