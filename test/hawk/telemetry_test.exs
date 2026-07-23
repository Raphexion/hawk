defmodule Hawk.TelemetryTest.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.TelemetryTest do
  use ExUnit.Case, async: false

  import Hawk.TestConn, only: [conn: 1]

  alias Hawk.Authority
  alias Hawk.TelemetryTest.CoursesController
  alias Videdal.Course

  @system Authority.system()

  @course_id Videdal.course_id()
  @short_id @course_id |> String.split("-") |> List.first()
  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  setup do
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    events = [
      [:hawk, :json_api, :controller, :show, :start],
      [:hawk, :json_api, :controller, :show, :stop],
      [:hawk, :json_api, :controller, :show, :exception],
      [:hawk, :json_api, :controller, :index, :start],
      [:hawk, :json_api, :controller, :index, :stop]
    ]

    :telemetry.attach_many(
      handler_id,
      events,
      &__MODULE__.handle_telemetry/4,
      %{test_pid: test_pid}
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "controller spans emit start and stop events with safe metadata" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn = CoursesController.show(conn(@system), %{"id" => @course_id})

    assert conn.status == 200

    assert_received {:hawk_telemetry, [:hawk, :json_api, :controller, :show, :start], start_measurements,
                     start_metadata}

    assert is_integer(start_measurements.system_time)
    assert start_metadata.action == :show
    assert start_metadata.resource == Videdal.Courses
    assert start_metadata.model == Videdal.Course
    assert start_metadata.id_kind == :uuid
    refute Map.has_key?(start_metadata, :id)

    assert_received {:hawk_telemetry, [:hawk, :json_api, :controller, :show, :stop], stop_measurements, stop_metadata}

    assert is_integer(stop_measurements.duration)
    assert stop_metadata.status == 200
    assert stop_metadata.result == :ok
    assert stop_metadata.id_kind == :uuid
    refute Map.has_key?(stop_metadata, :id)
  end

  test "short id show telemetry records id kind without exposing the prefix" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn = CoursesController.show(conn(@system), %{"id" => @short_id})

    assert conn.status == 200

    assert_received {:hawk_telemetry, [:hawk, :json_api, :controller, :show, :start], _measurements, metadata}

    assert metadata.id_kind == :short_id
    refute Map.has_key?(metadata, :id)
    refute Map.has_key?(metadata, :short_id)
  end

  test "bad request stop telemetry records status and result" do
    conn = CoursesController.show(conn(@system), %{"id" => "not-a-uuid"})

    assert conn.status == 400

    assert_received {:hawk_telemetry, [:hawk, :json_api, :controller, :show, :stop], _measurements, metadata}

    assert metadata.status == 400
    assert metadata.result == :bad_request
    assert metadata.id_kind == :invalid
  end

  test "controller index emits standard span events" do
    conn = CoursesController.index(conn(@system), %{})

    assert conn.status == 200

    assert_received {:hawk_telemetry, [:hawk, :json_api, :controller, :index, :start], _measurements,
                     %{action: :index, resource: Videdal.Courses, model: Videdal.Course}}

    assert_received {:hawk_telemetry, [:hawk, :json_api, :controller, :index, :stop], _measurements,
                     %{action: :index, status: 200, result: :ok}}
  end

  def handle_telemetry(event, measurements, metadata, %{test_pid: test_pid}) do
    send(test_pid, {:hawk_telemetry, event, measurements, metadata})
  end
end
