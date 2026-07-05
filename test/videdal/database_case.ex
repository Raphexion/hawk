defmodule Videdal.DatabaseCase do
  @moduledoc """
  Opt-in database test case for the Videdal example application.

  These tests use Hawk's existing Ecto SQL/Postgrex dependencies and stay under
  `test/videdal`, so the library remains repo-agnostic for host applications.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query
      import Videdal.DatabaseCase
    end
  end

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Videdal.SandboxRepo)
    :ok
  end

  def start_repo! do
    case Videdal.SandboxRepo.start_link() do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  def reset_schema! do
    repo = Videdal.SandboxRepo

    Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS grades", [])
    Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS enrollments", [])
    Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS parent_students", [])
    Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS parents", [])
    Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS courses", [])
    Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS students", [])
    Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS teachers", [])
    Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS schools", [])

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE TABLE schools (
        id bigserial PRIMARY KEY,
        name text NOT NULL
      )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE TABLE students (
        id bigserial PRIMARY KEY,
        name text NOT NULL,
        active boolean NOT NULL DEFAULT true,
        school_id bigint NOT NULL REFERENCES schools(id)
      )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE TABLE teachers (
        id bigserial PRIMARY KEY,
        name text NOT NULL,
        school_id bigint NOT NULL REFERENCES schools(id)
      )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE TABLE parents (
        id bigserial PRIMARY KEY,
        name text NOT NULL,
        school_id bigint NOT NULL REFERENCES schools(id)
      )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE TABLE parent_students (
        id bigserial PRIMARY KEY,
        school_id bigint NOT NULL REFERENCES schools(id),
        parent_id bigint NOT NULL REFERENCES parents(id),
        student_id bigint NOT NULL REFERENCES students(id)
      )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE TABLE courses (
        id bigserial PRIMARY KEY,
        title text NOT NULL,
        school_id bigint NOT NULL REFERENCES schools(id),
        teacher_id bigint NOT NULL REFERENCES teachers(id)
      )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE TABLE enrollments (
        id bigserial PRIMARY KEY,
        enrolled_on date,
        school_id bigint NOT NULL REFERENCES schools(id),
        student_id bigint NOT NULL REFERENCES students(id),
        course_id bigint NOT NULL REFERENCES courses(id)
      )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE TABLE grades (
        id bigserial PRIMARY KEY,
        score integer NOT NULL,
        school_id bigint NOT NULL REFERENCES schools(id),
        student_id bigint NOT NULL REFERENCES students(id),
        course_id bigint NOT NULL REFERENCES courses(id)
      )
      """,
      []
    )
  end

  def count_queries(fun) when is_function(fun, 0) do
    test_pid = self()
    ref = make_ref()
    handler_id = {__MODULE__, self(), ref}

    :telemetry.attach(
      handler_id,
      [:videdal, :sandbox_repo, :query],
      &__MODULE__.handle_query_event/4,
      %{test_pid: test_pid, ref: ref}
    )

    try do
      result = fun.()
      {result, drain_query_count(ref, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  def handle_query_event(_event, _measurements, metadata, %{test_pid: test_pid, ref: ref}) do
    unless metadata[:source] in ["schema_migrations"] do
      send(test_pid, {ref, :query})
    end
  end

  defp drain_query_count(ref, count) do
    receive do
      {^ref, :query} -> drain_query_count(ref, count + 1)
    after
      0 -> count
    end
  end
end
