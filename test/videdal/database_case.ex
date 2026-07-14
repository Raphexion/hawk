defmodule Videdal.DatabaseCase do
  @moduledoc """
  Opt-in database test case for the Videdal example application.

  These tests use Hawk's existing Ecto SQL/Postgrex dependencies and stay under
  `test/videdal`, so the library remains repo-agnostic for host applications.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Videdal.SandboxRepo

  using do
    quote do
      import Ecto.Query
      import Videdal.DatabaseCase
    end
  end

  setup _tags do
    :ok = Sandbox.checkout(SandboxRepo)
    :ok
  end

  def start_repo! do
    case SandboxRepo.start_link() do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  def reset_schema! do
    repo = SandboxRepo

    SQL.query!(repo, "DROP VIEW IF EXISTS course_grade_summaries", [])
    SQL.query!(repo, "DROP TABLE IF EXISTS grades", [])
    SQL.query!(repo, "DROP TABLE IF EXISTS enrollments", [])
    SQL.query!(repo, "DROP TABLE IF EXISTS parent_students", [])
    SQL.query!(repo, "DROP TABLE IF EXISTS parents", [])
    SQL.query!(repo, "DROP TABLE IF EXISTS courses", [])
    SQL.query!(repo, "DROP TABLE IF EXISTS students", [])
    SQL.query!(repo, "DROP TABLE IF EXISTS teachers", [])
    SQL.query!(repo, "DROP TABLE IF EXISTS schools", [])

    SQL.query!(
      repo,
      """
      CREATE TABLE schools (
        id uuid PRIMARY KEY,
        name text NOT NULL
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE students (
        id uuid PRIMARY KEY,
        name text NOT NULL,
        active boolean NOT NULL DEFAULT true,
        school_id uuid NOT NULL REFERENCES schools(id)
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE teachers (
        id uuid PRIMARY KEY,
        name text NOT NULL,
        school_id uuid NOT NULL REFERENCES schools(id)
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE parents (
        id uuid PRIMARY KEY,
        name text NOT NULL,
        school_id uuid NOT NULL REFERENCES schools(id)
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE parent_students (
        id uuid PRIMARY KEY,
        school_id uuid NOT NULL REFERENCES schools(id),
        parent_id uuid NOT NULL REFERENCES parents(id),
        student_id uuid NOT NULL REFERENCES students(id)
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE courses (
        id uuid PRIMARY KEY,
        title text NOT NULL,
        registration_state text NOT NULL DEFAULT 'draft',
        seat_count integer NOT NULL DEFAULT 0,
        waitlist_count integer NOT NULL DEFAULT 0,
        school_id uuid NOT NULL REFERENCES schools(id),
        teacher_id uuid NOT NULL REFERENCES teachers(id)
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE enrollments (
        id uuid PRIMARY KEY,
        enrolled_on date,
        registration_status text NOT NULL DEFAULT 'pending',
        school_id uuid NOT NULL REFERENCES schools(id),
        student_id uuid NOT NULL REFERENCES students(id),
        course_id uuid NOT NULL REFERENCES courses(id)
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE grades (
        id uuid PRIMARY KEY,
        score integer NOT NULL,
        school_id uuid NOT NULL REFERENCES schools(id),
        student_id uuid NOT NULL REFERENCES students(id),
        course_id uuid NOT NULL REFERENCES courses(id)
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE VIEW course_grade_summaries AS
      SELECT
        course_id AS id,
        school_id,
        course_id,
        count(*)::integer AS grade_count,
        avg(score)::float AS average_score
      FROM grades
      GROUP BY school_id, course_id
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
