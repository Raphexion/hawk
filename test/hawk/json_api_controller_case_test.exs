defmodule Hawk.JsonApiControllerCaseTest.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.JsonApiControllerCaseTest do
  use Hawk.JsonApiControllerCase,
    controller: Hawk.JsonApiControllerCaseTest.CoursesController,
    resource: Videdal.Courses,
    model: Videdal.Course,
    repo: Videdal.Repo,
    create_params: &__MODULE__.create_course_params/0

  import Hawk.TestConn, only: [resp: 1]

  pre_authorities do
    count = Process.get(:json_api_controller_case_pre_authorities_count, 0) + 1
    Process.put(:json_api_controller_case_pre_authorities_count, count)

    school =
      Videdal.Repo.insert!(%Videdal.School{id: Ecto.UUID.generate(), name: "Videdal Skole"})

    teacher =
      Videdal.Repo.insert!(%Videdal.Teacher{
        id: Ecto.UUID.generate(),
        name: "Ms. Curie",
        school_id: school.id
      })

    %{school_id: school.id, teacher_id: teacher.id}
  end

  authorities pre_authorities do
    assert Process.get(:json_api_controller_case_pre_authorities_count) == 1
    assert is_binary(pre_authorities.school_id)

    %{
      principal: Hawk.Authority.new(:principal, Videdal.principal_id()),
      school_admin:
        Hawk.Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: pre_authorities.school_id}),
      teacher:
        Hawk.Authority.new(:teacher, pre_authorities.teacher_id,
          scopes: %{school_id: pre_authorities.school_id, teacher_id: pre_authorities.teacher_id}
        ),
      unknown: Hawk.Authority.new(:unknown, Videdal.parent_id())
    }
  end

  pre_sample pre_authorities, authorities do
    count = Process.get(:json_api_controller_case_pre_sample_count, 0) + 1
    Process.put(:json_api_controller_case_pre_sample_count, count)

    %{school_id: pre_authorities.school_id, teacher_id: authorities.teacher.identity}
  end

  sample _pre_authorities, _authorities, known, index do
    %Videdal.Course{
      id: sample_id(index),
      title: "Course #{index}",
      school_id: known.school_id,
      teacher_id: known.teacher_id
    }
  end

  test "sample generator builds multiple related models" do
    pre = pre_authorities()

    [first, second, third] = sample_models(3)
    assert {first.id, second.id, third.id} == {sample_id(1), sample_id(2), sample_id(3)}
    assert Enum.all?([first, second, third], &(&1.school_id == pre.school_id))
  end

  test "generate_sample reuses pre_sample context inside one test" do
    Process.delete(:json_api_controller_case_pre_sample_count)

    first = generate_sample(1)
    second = generate_sample(2)

    assert {first.id, second.id} == {sample_id(1), sample_id(2)}
    assert Process.get(:json_api_controller_case_pre_sample_count) == 1
  end

  test "public authority is available even when not listed explicitly" do
    put_json_api_results([sample_model()])

    conn = controller().show(conn_for(:public), %{"id" => sample_id(1)})

    assert conn.status == 200
    assert resp(conn).data.id == sample_id(1)
  end

  test "specific controller behaviour can be tested beside the generated matrix" do
    put_json_api_results([sample_model()])

    conn = controller().show(conn_for(:principal), %{"id" => sample_id(1)})

    assert conn.status == 200

    assert resp(conn).data.attributes == %{
             title: "Course 1",
             registration_state: "draft",
             seat_count: 0,
             waitlist_count: 0
           }
  end

  defp sample_id(1), do: Videdal.course_id()
  defp sample_id(2), do: Videdal.other_course_id()
  defp sample_id(3), do: Videdal.enrollment_id()

  def create_course_params do
    pre = pre_authorities()

    %{
      "data" => %{
        "type" => "courses",
        "attributes" => %{"title" => "Math"},
        "relationships" => %{
          "school" => %{"data" => %{"type" => "schools", "id" => pre.school_id}},
          "teacher" => %{"data" => %{"type" => "teachers", "id" => pre.teacher_id}}
        }
      }
    }
  end
end
