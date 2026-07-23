defmodule Videdal.Controllers.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Videdal.Controllers.CoursesControllerTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Videdal.Controllers.CoursesController
  alias Videdal.Course

  @course_id Videdal.course_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()
  @school_admin Hawk.Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: Videdal.school_id()})

  test "index returns a JSON:API collection document" do
    courses = [
      %Course{
        id: @course_id,
        title: "Math",
        school_id: @school_id,
        teacher_id: @teacher_id,
        registration_state: "draft",
        seat_count: 0,
        waitlist_count: 0
      }
    ]

    Process.put({Videdal.Repo, :all_results}, courses)

    conn = CoursesController.index(conn(@school_admin), %{"sort" => "title", "page" => %{"size" => "10"}})

    assert conn.status == 200

    assert resp(conn) == %{
             data: [
               %{
                 type: "courses",
                 id: @course_id,
                 attributes: %{
                   title: "Math",
                   registration_state: "draft",
                   seat_count: 0,
                   waitlist_count: 0
                 },
                 relationships: %{
                   school: %{data: %{type: "schools", id: @school_id}},
                   teacher: %{data: %{type: "teachers", id: @teacher_id}},
                   grades: %{data: []},
                   enrollments: %{data: []}
                 }
               }
             ],
             meta: %{page: %{number: 1, size: 10, count: 1}}
           }

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "order_by: [asc: c0.title]"
    assert inspected =~ "limit: ^10"
  end

  test "show returns one JSON:API resource document" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 0,
      waitlist_count: 0
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn = CoursesController.show(conn(@school_admin), %{"id" => @course_id})

    assert conn.status == 200
    assert resp(conn).data.type == "courses"
    assert resp(conn).data.id == @course_id

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "draft",
             seat_count: 0,
             waitlist_count: 0
           }
  end

  test "show returns a JSON:API error when missing" do
    Process.put({Videdal.Repo, :all_results}, [])

    conn = CoursesController.show(conn(@school_admin), %{"id" => Videdal.other_course_id()})

    assert conn.status == 404

    assert resp(conn) == %{
             errors: [
               %{
                 status: "404",
                 code: "not_found",
                 title: "Not found",
                 detail: "course was not found"
               }
             ]
           }
  end

  test "create writes through the resource writer and returns JSON:API" do
    conn =
      CoursesController.create(conn(@school_admin), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "schools", "id" => @school_id}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => @teacher_id}}
          }
        }
      })

    assert conn.status == 201

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "draft",
             seat_count: 0,
             waitlist_count: 0
           }

    assert_received {:videdal_repo, :insert, changeset}
    assert changeset.changes == %{title: "Math", school_id: @school_id, teacher_id: @teacher_id}
  end

  test "open-registration action ignores malformed non-map meta payloads and preserves existing counts" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 3,
      waitlist_count: 2
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      CoursesController.action(conn(@school_admin), %{
        "id" => @course_id,
        "action" => "open-registration",
        "meta" => "not-a-map"
      })

    assert conn.status == 200

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "open",
             seat_count: 3,
             waitlist_count: 2
           }

    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{registration_state: "open"}
  end

  test "open-registration action accepts JSON:API meta and returns the updated resource" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 0,
      waitlist_count: 0
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      CoursesController.action(conn(@school_admin), %{
        "id" => @course_id,
        "action" => "open-registration",
        "meta" => %{"seat_count" => 2, "waitlist_count" => 1}
      })

    assert conn.status == 200

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "open",
             seat_count: 2,
             waitlist_count: 1
           }

    assert_received {:videdal_repo, :update, changeset}

    assert changeset.changes == %{
             registration_state: "open",
             seat_count: 2,
             waitlist_count: 1
           }
  end

  test "open-registration action without meta preserves existing counts" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 4,
      waitlist_count: 2
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      CoursesController.action(conn(@school_admin), %{
        "id" => @course_id,
        "action" => "open-registration"
      })

    assert conn.status == 200

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "open",
             seat_count: 4,
             waitlist_count: 2
           }

    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{registration_state: "open"}
  end

  test "unknown action returns a JSON:API action_not_found error" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 0,
      waitlist_count: 0
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      CoursesController.action(conn(@school_admin), %{
        "id" => @course_id,
        "action" => "launch-rocket",
        "meta" => %{}
      })

    assert conn.status == 404

    assert resp(conn) == %{
             errors: [
               %{
                 status: "404",
                 code: "action_not_found",
                 title: "Not found",
                 detail: "launch-rocket is not a supported action for course"
               }
             ]
           }
  end

  test "close-registration action rejects courses that are not open" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 2,
      waitlist_count: 1
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      CoursesController.action(conn(@school_admin), %{
        "id" => @course_id,
        "action" => "close-registration",
        "meta" => %{}
      })

    assert conn.status == 422

    assert [
             %{
               status: "422",
               code: "invalid",
               source: %{pointer: "/data/attributes/registration_state"}
             }
           ] = resp(conn).errors

    refute_received {:videdal_repo, :transaction}
  end

  test "missing course on action routes returns the resource not_found error" do
    Process.put({Videdal.Repo, :all_results}, [])

    conn =
      CoursesController.action(conn(@school_admin), %{
        "id" => @course_id,
        "action" => "open-registration",
        "meta" => %{"seat_count" => 2, "waitlist_count" => 1}
      })

    assert conn.status == 404

    assert resp(conn) == %{
             errors: [
               %{
                 status: "404",
                 code: "not_found",
                 title: "Not found",
                 detail: "course was not found"
               }
             ]
           }
  end

  test "close-registration action finalizes enrollments into enrolled, waitlisted, and rejected" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "open",
      seat_count: 2,
      waitlist_count: 1
    }

    enrollments = [
      %Videdal.Enrollment{
        id: "enrollment-1",
        school_id: @school_id,
        course_id: @course_id,
        student_id: @student_id,
        enrolled_on: ~D[2026-01-01],
        registration_status: "pending"
      },
      %Videdal.Enrollment{
        id: "enrollment-2",
        school_id: @school_id,
        course_id: @course_id,
        student_id: Videdal.other_student_id(),
        enrolled_on: ~D[2026-01-02],
        registration_status: "pending"
      },
      %Videdal.Enrollment{
        id: "enrollment-3",
        school_id: @school_id,
        course_id: @course_id,
        student_id: "00000000-0000-0000-0000-000000000011",
        enrolled_on: ~D[2026-01-03],
        registration_status: "pending"
      },
      %Videdal.Enrollment{
        id: "enrollment-4",
        school_id: @school_id,
        course_id: @course_id,
        student_id: "00000000-0000-0000-0000-000000000015",
        enrolled_on: ~D[2026-01-04],
        registration_status: "pending"
      }
    ]

    Process.put({Videdal.Repo, :all_results, Videdal.Course}, [course])
    Process.put({Videdal.Repo, :all_results, Videdal.Enrollment}, enrollments)

    conn =
      CoursesController.action(conn(@school_admin), %{
        "id" => @course_id,
        "action" => "close-registration",
        "meta" => %{}
      })

    assert conn.status == 200

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "closed",
             seat_count: 2,
             waitlist_count: 1
           }

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :all, _query}

    update_changes =
      Enum.map(1..5, fn _ ->
        assert_received {:videdal_repo, :update, changeset}
        changeset.changes
      end)

    assert %{registration_state: "closed"} in update_changes

    enrollment_changes = Enum.reject(update_changes, &Map.has_key?(&1, :registration_state))

    assert Enum.frequencies(enrollment_changes) == %{
             %{registration_status: "enrolled"} => 2,
             %{registration_status: "waitlisted"} => 1,
             %{registration_status: "rejected"} => 1
           }
  end

  test "update returns JSON:API validation errors" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 0,
      waitlist_count: 0
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      CoursesController.update(
        conn(%{role: :student, scopes: %{school_id: @school_id, student_id: @student_id}}),
        %{"id" => @course_id, "data" => %{}}
      )

    assert conn.status == 403
    assert [%{status: "403", code: "not_authorized"}] = resp(conn).errors
  end

end
