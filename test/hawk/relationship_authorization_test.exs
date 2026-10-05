defmodule Hawk.RelationshipAuthorizationTest.Writer do
  use Hawk.Writer.Resource,
    model: Videdal.Enrollment,
    repo: Videdal.Repo,
    policy: Videdal.Enrollments.Policy

  create do
    cast([:school_id, :student_id, :course_id])
    validate_required([:school_id, :student_id, :course_id])
    authorize_relationships([:student])
    authorize_relationships([:course])
  end

  update do
    cast([:student_id, :course_id])
    authorize_relationships([:student, :course])
  end
end

defmodule Hawk.RelationshipAuthorizationTest.ActiveStudents do
  use Hawk.Reader.Resource,
    schema: Videdal.Student,
    repo: Videdal.Repo,
    policy: Videdal.Students.Policy

  filter(:id)
  filter(:school_id)
  filter(:active)
  soft_delete(:deleted_at)

  def scope(query, _params, _opts), do: where(query, [root: student], student.active == true)
end

defmodule Hawk.RelationshipAuthorizationTest.OtherRepoStudents do
  use Hawk.Reader.Resource,
    schema: Videdal.Student,
    repo: OtherRepo,
    policy: Videdal.Students.Policy

  filter(:id)
  filter(:school_id)
  filter(:active)
end

defmodule Hawk.RelationshipAuthorizationTest.DeniedPolicy do
  use Hawk.Policy

  read do
    role(:system, :all)
  end

  write(:never)
end

defmodule Hawk.RelationshipAuthorizationTest.DeniedStudents do
  use Hawk.Reader.Resource,
    schema: Videdal.Student,
    repo: Videdal.Repo,
    policy: Hawk.RelationshipAuthorizationTest.DeniedPolicy

  filter(:id)
end

defmodule Hawk.RelationshipAuthorizationTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.{Authority, MutationContext, Writer}
  alias Hawk.RelationshipAuthorizationTest.Writer, as: EnrollmentWriter

  setup do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})
    attrs = %{school_id: school.id, student_id: student.id, course_id: course.id}
    {:ok, attrs: attrs, authority: authority, student: student, course: course}
  end

  test "checks both references in one query without persisting", %{attrs: attrs, authority: authority} do
    {changeset, count} = count_queries(fn -> EnrollmentWriter.change_create(attrs, authority) end)
    assert changeset.valid?
    assert count == 1
  end

  test "persists authorized references", %{attrs: attrs, authority: authority} do
    assert {:ok, enrollment} = EnrollmentWriter.create(attrs, authority)
    assert enrollment.student_id == attrs.student_id
  end

  test "denies another tenant's reference", %{attrs: attrs, authority: authority} do
    other = insert(:student)
    assert {:not_authorized, context} = EnrollmentWriter.create(%{attrs | student_id: other.id}, authority)
    assert context.policy_validated?
  end

  test "form validation rejects inaccessible references", %{attrs: attrs, authority: authority} do
    other = insert(:course)
    changeset = EnrollmentWriter.change_create(%{attrs | course_id: other.id}, authority)
    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :base)
  end

  test "missing tenant scopes fail closed", %{attrs: attrs} do
    assert {:not_authorized, _} = EnrollmentWriter.create(attrs, Authority.new(:school_admin, 1))
  end

  test "denies nonexistent references", %{attrs: attrs, authority: authority} do
    assert {:not_authorized, _} = EnrollmentWriter.create(%{attrs | course_id: Ecto.UUID.generate()}, authority)
  end

  test "denies deleted references even for system authority", %{attrs: attrs, student: student} do
    Repo.update!(Ecto.Changeset.change(student, deleted_at: DateTime.utc_now(:second)))
    assert {:not_authorized, _} = EnrollmentWriter.create(attrs, Authority.system())
  end

  test "checks the effective reference values on update", %{attrs: attrs, authority: authority} do
    enrollment = insert(:enrollment, attrs)
    other = insert(:course)
    assert {:not_authorized, _} = EnrollmentWriter.update(enrollment, %{course_id: other.id}, authority)
    assert Repo.get!(Videdal.Enrollment, enrollment.id).course_id == attrs.course_id
    assert EnrollmentWriter.change_update(enrollment, %{}, authority).valid?
  end

  test "invalid input performs no authorization query", %{attrs: attrs, authority: authority} do
    {result, count} = count_queries(fn -> EnrollmentWriter.create(%{attrs | student_id: "bad"}, authority) end)
    assert {:invalid, _} = result
    assert count == 0
  end

  test "write policy denial performs no authorization query", %{attrs: attrs} do
    authority = Authority.new(:public, 1)
    {result, count} = count_queries(fn -> EnrollmentWriter.create(attrs, authority) end)
    assert {:not_authorized, _} = result
    assert count == 0
  end

  test "readonly authorities perform no authorization query", %{attrs: attrs, authority: authority} do
    {result, count} = count_queries(fn -> EnrollmentWriter.create(attrs, %{authority | readonly?: true}) end)
    assert {:not_authorized, _} = result
    assert count == 0
  end

  test "optional nil references and empty declarations need no query" do
    context = MutationContext.create(%Videdal.Enrollment{}, %{}, Authority.system())
    {result, count} = count_queries(fn -> Writer.authorize_relationships(context, [:student], Repo) end)
    assert result.error == :none
    assert Writer.authorize_relationships(context, [], Repo) == context
    assert count == 0
  end

  test "rejects non-belongs-to declarations" do
    context = MutationContext.create(%Videdal.Course{}, %{}, Authority.system())
    assert_raise ArgumentError, ~r/belongs_to/, fn -> Writer.authorize_relationships(context, [:grades], Repo) end
  end

  test "rejects a reader for another schema", %{attrs: attrs, authority: authority} do
    context = MutationContext.create(%Videdal.Enrollment{}, attrs, authority) |> Writer.cast(Map.keys(attrs))

    assert_raise ArgumentError, ~r/associated schema/, fn ->
      Writer.authorize_relationships(context, [student: Videdal.Courses.Reader], Repo)
    end
  end

  test "rejects a reader from another repository", %{attrs: attrs, authority: authority} do
    context = MutationContext.create(%Videdal.Enrollment{}, attrs, authority) |> Writer.cast(Map.keys(attrs))

    assert_raise ArgumentError, ~r/writer's repo/, fn ->
      Writer.authorize_relationships(context, [student: Hawk.RelationshipAuthorizationTest.OtherRepoStudents], Repo)
    end
  end

  test "denied read policies cannot be bypassed by a permitted write role", %{attrs: attrs, authority: authority} do
    context = MutationContext.create(%Videdal.Enrollment{}, attrs, authority) |> Writer.cast(Map.keys(attrs))

    result =
      Writer.authorize_relationships(context, [student: Hawk.RelationshipAuthorizationTest.DeniedStudents], Repo)

    assert result.error == :not_authorized
  end

  test "an explicit reader can narrow reference eligibility", %{attrs: attrs, authority: authority, student: student} do
    Repo.update!(Ecto.Changeset.change(student, active: false))
    context = MutationContext.create(%Videdal.Enrollment{}, attrs, authority) |> Writer.cast(Map.keys(attrs))

    result =
      Writer.authorize_relationships(context, [student: Hawk.RelationshipAuthorizationTest.ActiveStudents], Repo)

    assert result.error == :not_authorized
  end
end
