defmodule Videdal.Controllers.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Videdal.Controllers.CoursesControllerTest do
  use Videdal.DatabaseCase, async: true

  import Ecto.Query
  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Videdal.Controllers.CoursesController
  alias Videdal.{Course, Enrollment, Repo}

  test "index returns a JSON:API collection document" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      CoursesController.index(conn(school_admin(school)), %{
        "sort" => "title",
        "page" => %{"size" => "10"}
      })

    assert conn.status == 200

    assert resp(conn) == %{
             data: [
               %{
                 type: "courses",
                 id: course.id,
                 attributes: %{
                   title: "Math",
                   registration_state: "draft",
                   seat_count: 0,
                   waitlist_count: 0
                 },
                 relationships: %{
                   school: %{data: %{type: "schools", id: school.id}},
                   teacher: %{data: %{type: "teachers", id: teacher.id}},
                   grades: %{data: []},
                   enrollments: %{data: []}
                 }
               }
             ],
             meta: %{page: %{number: 1, size: 10, count: 1}}
           }
  end

  test "show returns one JSON:API resource document" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn = CoursesController.show(conn(school_admin(school)), %{"id" => course.id})

    assert conn.status == 200
    assert resp(conn).data.type == "courses"
    assert resp(conn).data.id == course.id

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "draft",
             seat_count: 0,
             waitlist_count: 0
           }
  end

  test "index applies sparse fieldsets from controller params" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      CoursesController.index(conn(school_admin(school)), %{
        "fields" => %{"courses" => "title,teacher"}
      })

    assert conn.status == 200
    assert [resource] = resp(conn).data
    assert resource.attributes == %{title: "Math"}
    assert resource.relationships == %{teacher: %{data: %{type: "teachers", id: teacher.id}}}
  end

  test "show applies sparse fieldsets from controller params" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      CoursesController.show(conn(school_admin(school)), %{
        "id" => course.id,
        "fields" => %{"courses" => "title"}
      })

    assert conn.status == 200
    assert resp(conn).data.attributes == %{title: "Math"}
    assert resp(conn).data.relationships == %{}
  end

  test "show returns a JSON:API error when missing" do
    conn =
      CoursesController.show(conn(Authority.system()), %{"id" => Videdal.other_course_id()})

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
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    conn =
      CoursesController.create(conn(school_admin(school)), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "schools", "id" => school.id}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => teacher.id}}
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

    created_id = resp(conn).data.id
    assert Repo.get!(Course, created_id).title == "Math"
  end

  test "open-registration action ignores malformed non-map meta payloads and preserves existing counts" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    course =
      insert(:course,
        school_id: school.id,
        teacher_id: teacher.id,
        title: "Math",
        registration_state: "draft",
        seat_count: 3,
        waitlist_count: 2
      )

    conn =
      CoursesController.hawk_action(conn(school_admin(school)), %{
        "id" => course.id,
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

    reloaded = Repo.get!(Course, course.id)
    assert reloaded.registration_state == "open"
    assert reloaded.seat_count == 3
    assert reloaded.waitlist_count == 2
  end

  test "open-registration action accepts JSON:API meta and returns the updated resource" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    course =
      insert(:course,
        school_id: school.id,
        teacher_id: teacher.id,
        title: "Math",
        registration_state: "draft",
        seat_count: 0,
        waitlist_count: 0
      )

    conn =
      CoursesController.hawk_action(conn(school_admin(school)), %{
        "id" => course.id,
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

    reloaded = Repo.get!(Course, course.id)
    assert reloaded.registration_state == "open"
    assert reloaded.seat_count == 2
    assert reloaded.waitlist_count == 1
  end

  test "open-registration action without meta preserves existing counts" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    course =
      insert(:course,
        school_id: school.id,
        teacher_id: teacher.id,
        title: "Math",
        registration_state: "draft",
        seat_count: 4,
        waitlist_count: 2
      )

    conn =
      CoursesController.hawk_action(conn(school_admin(school)), %{
        "id" => course.id,
        "action" => "open-registration"
      })

    assert conn.status == 200

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "open",
             seat_count: 4,
             waitlist_count: 2
           }

    reloaded = Repo.get!(Course, course.id)
    assert reloaded.registration_state == "open"
    assert reloaded.seat_count == 4
    assert reloaded.waitlist_count == 2
  end

  test "unknown action returns a JSON:API action_not_found error" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      CoursesController.hawk_action(conn(school_admin(school)), %{
        "id" => course.id,
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
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    course =
      insert(:course,
        school_id: school.id,
        teacher_id: teacher.id,
        title: "Math",
        registration_state: "draft",
        seat_count: 2,
        waitlist_count: 1
      )

    conn =
      CoursesController.hawk_action(conn(school_admin(school)), %{
        "id" => course.id,
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

    # no transaction ran: the course is still draft
    assert Repo.get!(Course, course.id).registration_state == "draft"
  end

  test "missing course on action routes returns the resource not_found error" do
    conn =
      CoursesController.hawk_action(conn(Authority.system()), %{
        "id" => Videdal.course_id(),
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
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    course =
      insert(:course,
        school_id: school.id,
        teacher_id: teacher.id,
        title: "Math",
        registration_state: "open",
        seat_count: 2,
        waitlist_count: 1
      )

    student1 = insert(:student, school_id: school.id)
    student2 = insert(:student, school_id: school.id)
    student3 = insert(:student, school_id: school.id)
    student4 = insert(:student, school_id: school.id)

    insert(:enrollment,
      school_id: school.id,
      course_id: course.id,
      student_id: student1.id,
      enrolled_on: ~D[2026-01-01]
    )

    insert(:enrollment,
      school_id: school.id,
      course_id: course.id,
      student_id: student2.id,
      enrolled_on: ~D[2026-01-02]
    )

    insert(:enrollment,
      school_id: school.id,
      course_id: course.id,
      student_id: student3.id,
      enrolled_on: ~D[2026-01-03]
    )

    insert(:enrollment,
      school_id: school.id,
      course_id: course.id,
      student_id: student4.id,
      enrolled_on: ~D[2026-01-04]
    )

    conn =
      CoursesController.hawk_action(conn(school_admin(school)), %{
        "id" => course.id,
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

    assert Repo.get!(Course, course.id).registration_state == "closed"

    statuses =
      from(e in Enrollment, where: e.course_id == ^course.id, order_by: [asc: e.enrolled_on, asc: e.id])
      |> Repo.all()
      |> Enum.map(& &1.registration_status)

    assert Enum.frequencies(statuses) == %{
             "enrolled" => 2,
             "waitlisted" => 1,
             "rejected" => 1
           }
  end

  test "update returns JSON:API validation errors" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      CoursesController.update(
        conn(%{role: :student, scopes: %{school_id: school.id, student_id: student.id}}),
        %{"id" => course.id, "data" => %{}}
      )

    assert conn.status == 403
    assert [%{status: "403", code: "not_authorized"}] = resp(conn).errors
  end

  defp school_admin(school) do
    Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: school.id})
  end
end

defmodule Videdal.Controllers.CoursesControllerDryRunTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestConn, only: [conn: 1]

  alias Hawk.Authority
  alias Videdal.Controllers.CoursesController
  alias Videdal.{Course, Grade, Repo}

  @authority Authority.system()

  test "submit-grade dry-run validates without committing and reports errors" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      CoursesController.hawk_action(conn(@authority), %{
        "id" => course.id,
        "action" => "submit-grade",
        "dry-run" => true,
        "meta" => %{"score" => 7, "student_id" => nil}
      })

    assert conn.status == 422
    assert %{"errors" => errors} = Jason.decode!(conn.resp_body)
    assert Enum.any?(errors, &String.contains?(&1["source"]["pointer"], "student_id"))
    assert Repo.all(Grade) == []
    assert Repo.get!(Course, course.id).title == "Math"
  end

  test "submit-grade dry-run returns 200 when all params are valid" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      CoursesController.hawk_action(conn(@authority), %{
        "id" => course.id,
        "action" => "submit-grade",
        "dry-run" => true,
        "meta" => %{"score" => 7, "student_id" => student.id}
      })

    assert conn.status == 200
    assert Repo.all(Grade) == []
  end

  test "submit-grade without dry-run commits" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      CoursesController.hawk_action(conn(@authority), %{
        "id" => course.id,
        "action" => "submit-grade",
        "meta" => %{"score" => 7, "student_id" => student.id}
      })

    assert conn.status == 200
    assert [grade] = Repo.all(Grade)
    assert grade.score == 7
    assert Repo.get!(Course, course.id).title == "Math (graded)"
  end

  test "a run-only action dry-run is rejected with 400" do
    course =
      insert(:course,
        school_id: insert(:school).id,
        teacher_id: insert(:teacher).id,
        registration_state: "draft",
        seat_count: 0,
        waitlist_count: 0
      )

    conn =
      CoursesController.hawk_action(conn(@authority), %{
        "id" => course.id,
        "action" => "open-registration",
        "dry-run" => true,
        "meta" => %{"seat_count" => 2, "waitlist_count" => 1}
      })

    assert conn.status == 400
  end
end
