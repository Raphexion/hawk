defmodule Hawk.ActionsTest.DemoResource do
end

defmodule Hawk.ActionsTest.DemoResource.Actions do
  use Hawk.Actions

  action("ping",
    doc: "Ping the resource with a counted command.",
    params: [count: [type: :integer, doc: "How many times to ping.", example: 3]]
  )

  action("custom-handler",
    handler: :run_custom,
    params: [message: [type: :string, example: "hello"]]
  )

  def ping(model, params, authority), do: {:ok, model.id, params, authority.role}
  def run_custom(model, params, authority), do: {:custom, model.title, params, authority.identity}
end

defmodule Hawk.ActionsTest.DuplicateResource do
end

defmodule Hawk.ActionsTest.DuplicateResource.Actions do
  use Hawk.Actions

  action("ping", doc: "first")
  action("ping", doc: "second", handler: :second_ping)
end

defmodule Hawk.ActionsTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority

  test "resource actions expose metadata for dispatch and OpenAPI" do
    assert Hawk.Actions.actions(Hawk.ActionsTest.DemoResource) == %{
             "ping" => %{
               name: "ping",
               handler: :ping,
               doc: "Ping the resource with a counted command.",
               params: %{
                 count: %{type: :integer, doc: "How many times to ping.", example: 3}
               }
             },
             "custom-handler" => %{
               name: "custom-handler",
               handler: :run_custom,
               doc: nil,
               params: %{
                 message: %{type: :string, example: "hello"}
               }
             }
           }
  end

  test "dispatch atomizes only declared params and supports default and custom handlers" do
    course = %Videdal.Course{id: "course-1", title: "Math"}
    authority = Authority.new(:school_admin, "admin-1", scopes: %{school_id: "school-1"})

    assert Hawk.Actions.dispatch(
             Hawk.ActionsTest.DemoResource,
             "ping",
             course,
             %{"count" => 2, "ignored" => "nope"},
             authority
           ) == {:ok, "course-1", %{count: 2}, :school_admin}

    assert Hawk.Actions.dispatch(
             Hawk.ActionsTest.DemoResource,
             "custom-handler",
             course,
             %{"message" => "hello", "ignored" => "nope"},
             authority
           ) == {:custom, "Math", %{message: "hello"}, "admin-1"}
  end

  test "dispatch accepts atom keys in meta params too" do
    course = %Videdal.Course{id: "course-1", title: "Math"}

    assert Hawk.Actions.dispatch(
             Hawk.ActionsTest.DemoResource,
             "ping",
             course,
             %{count: 4, ignored: "nope"},
             Authority.system()
           ) == {:ok, "course-1", %{count: 4}, :system}
  end

  test "dispatch ignores hostile undeclared params without creating atoms" do
    hostile = "hawk_hostile_action_#{System.unique_integer([:positive])}"
    course = %Videdal.Course{id: "course-1", title: "Math"}

    assert Hawk.Actions.dispatch(
             Hawk.ActionsTest.DemoResource,
             "ping",
             course,
             %{"count" => 4, hostile => "boom"},
             Authority.system()
           ) == {:ok, "course-1", %{count: 4}, :system}

    assert_raise ArgumentError, fn -> String.to_existing_atom(hostile) end
  end

  test "duplicate action names currently keep the last declaration" do
    assert Hawk.Actions.actions(Hawk.ActionsTest.DuplicateResource) == %{
             "ping" => %{
               name: "ping",
               handler: :second_ping,
               doc: "second",
               params: %{}
             }
           }
  end

  test "resources without actions modules or unknown action names return unknown_action" do
    course = %Videdal.Course{id: "course-1", title: "Math"}
    authority = Authority.system()

    assert Hawk.Actions.actions(Videdal.Grades) == %{}

    assert Hawk.Actions.dispatch(Videdal.Grades, "ping", course, %{}, authority) ==
             :unknown_action

    assert Hawk.Actions.dispatch(Hawk.ActionsTest.DemoResource, "missing", course, %{}, authority) ==
             :unknown_action
  end
end
