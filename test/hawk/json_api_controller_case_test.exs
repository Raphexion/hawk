defmodule Hawk.JsonApiControllerCaseTest.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiControllerCaseTest do
  use Hawk.JsonApiControllerCase,
    controller: Hawk.JsonApiControllerCaseTest.CoursesController,
    resource: Videdal.Courses,
    model: Videdal.Course,
    repo: Videdal.Repo

  pre_authorities do
    count = Process.get(:json_api_controller_case_pre_authorities_count, 0) + 1
    Process.put(:json_api_controller_case_pre_authorities_count, count)

    %{school_id: 7, teacher_id: 12}
  end

  authorities pre_authorities do
    assert Process.get(:json_api_controller_case_pre_authorities_count) == 1
    assert pre_authorities.school_id == 7

    %{
      principal: Hawk.Authority.new(:principal, 1),
      school_admin: Hawk.Authority.new(:school_admin, 2, scopes: %{school_id: 7}),
      teacher: Hawk.Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12}),
      unknown: Hawk.Authority.new(:unknown, 99)
    }
  end

  pre_sample pre_authorities, authorities do
    count = Process.get(:json_api_controller_case_pre_sample_count, 0) + 1
    Process.put(:json_api_controller_case_pre_sample_count, count)

    %{school_id: pre_authorities.school_id, teacher_id: authorities.teacher.identity}
  end

  sample _pre_authorities, _authorities, known, index do
    %Videdal.Course{
      id: index,
      title: "Course #{index}",
      school_id: known.school_id,
      teacher_id: known.teacher_id
    }
  end

  test "sample generator builds multiple related models" do
    assert [first, second, third] = sample_models(3)
    assert {first.id, second.id, third.id} == {1, 2, 3}
    assert Enum.all?([first, second, third], &(&1.school_id == 7))
  end

  test "generate_sample reuses pre_sample context inside one test" do
    Process.delete(:json_api_controller_case_pre_sample_count)

    first = generate_sample(1)
    second = generate_sample(2)

    assert {first.id, second.id} == {1, 2}
    assert Process.get(:json_api_controller_case_pre_sample_count) == 1
  end

  test "public authority is available even when not listed explicitly" do
    put_json_api_results([sample_model()])

    conn = controller().show(conn_for(:public), %{"id" => "1"})

    assert conn.status == 200
    assert conn.resp_body.data.id == "1"
  end

  test "specific controller behaviour can be tested beside the generated matrix" do
    put_json_api_results([sample_model()])

    conn = controller().show(conn_for(:principal), %{"id" => "1"})

    assert conn.status == 200
    assert conn.resp_body.data.attributes == %{title: "Course 1"}
  end
end
