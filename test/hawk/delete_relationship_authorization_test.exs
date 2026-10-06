defmodule Hawk.DeleteRelationshipAuthorizationTest.EnrollmentWriter do
  use Hawk.Writer.Resource,
    model: Videdal.Enrollment,
    repo: Videdal.Repo,
    policy: Videdal.Enrollments.Policy

  create do
    cast([:school_id, :student_id, :course_id])
  end

  delete do
    authorize_relationships([:student])
    authorize_relationships([:course])
  end
end

defmodule Hawk.DeleteRelationshipAuthorizationTest.ActiveStudents do
  use Hawk.Reader.Resource,
    schema: Videdal.Student,
    repo: Videdal.Repo,
    policy: Videdal.Students.Policy

  filter(:id)
  filter(:school_id)
  soft_delete(:deleted_at)

  def scope(query, _params, _opts), do: where(query, [root: student], student.active == true)
end

defmodule Hawk.DeleteRelationshipAuthorizationTest.NarrowWriter do
  use Hawk.Writer.Resource,
    model: Videdal.Enrollment,
    repo: Videdal.Repo,
    policy: Videdal.Enrollments.Policy

  create do
    cast([:student_id])
  end

  delete do
    authorize_relationships(student: Hawk.DeleteRelationshipAuthorizationTest.ActiveStudents)
  end
end

defmodule Hawk.DeleteRelationshipAuthorizationTest.StudentWriter do
  use Hawk.Writer.Resource,
    model: Videdal.Student,
    repo: Videdal.Repo,
    policy: Videdal.Students.Policy

  create do
    cast([:name, :school_id])
  end

  delete do
    authorize_relationships([:school])
  end

  soft_delete(:deleted_at)
end

defmodule Hawk.DeleteRelationshipAuthorizationTest.SoftFirstWriter do
  use Hawk.Writer.Resource,
    model: Videdal.Student,
    repo: Videdal.Repo,
    policy: Videdal.Students.Policy

  create do
    cast([:name, :school_id])
  end

  soft_delete(:deleted_at)

  delete do
    authorize_relationships([:school])
  end
end

defmodule Hawk.DeleteRelationshipAuthorizationTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Hawk.DeleteRelationshipAuthorizationTest.{EnrollmentWriter, NarrowWriter, SoftFirstWriter, StudentWriter}

  setup do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id)
    enrollment = insert(:enrollment, school_id: school.id, student_id: student.id, course_id: course.id)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})
    {:ok, enrollment: enrollment, student: student, authority: authority}
  end

  test "delete checks multiple declarations in one query before persistence", %{
    enrollment: enrollment,
    authority: authority
  } do
    {result, queries} = capture_queries(fn -> EnrollmentWriter.delete(enrollment, authority) end)
    assert {:ok, deleted} = result
    assert deleted.id == enrollment.id
    assert [authorization, "begin", deletion, "commit"] = queries
    assert authorization =~ "SELECT TRUE"
    assert String.downcase(authorization) =~ "exists"
    assert deletion =~ "DELETE FROM"
    refute Repo.get(Videdal.Enrollment, enrollment.id)
  end

  test "delete denies another tenant's relationship without persistence", %{
    enrollment: enrollment,
    authority: authority
  } do
    other_course = insert(:course)
    enrollment = Repo.update!(Ecto.Changeset.change(enrollment, course_id: other_course.id))
    {result, count} = count_queries(fn -> EnrollmentWriter.delete(enrollment, authority) end)
    assert {:not_authorized, context} = result
    refute context.changeset.valid?
    assert count == 1
    assert Repo.get(Videdal.Enrollment, enrollment.id)
  end

  test "delete retains related lifecycle filters for system authority", %{enrollment: enrollment, student: student} do
    Repo.update!(Ecto.Changeset.change(student, deleted_at: DateTime.utc_now(:second)))
    assert {:not_authorized, _} = EnrollmentWriter.delete(enrollment, Authority.system())
    assert Repo.get(Videdal.Enrollment, enrollment.id)
  end

  test "delete supports reader overrides", %{enrollment: enrollment, student: student, authority: authority} do
    Repo.update!(Ecto.Changeset.change(student, active: false))
    assert {:not_authorized, _} = NarrowWriter.delete(enrollment, authority)
    assert Repo.get(Videdal.Enrollment, enrollment.id)
  end

  test "denied write roles and readonly actors perform no query", %{enrollment: enrollment, authority: authority} do
    for actor <- [Authority.public(), Authority.readonly(authority)] do
      {result, count} = count_queries(fn -> EnrollmentWriter.delete(enrollment, actor) end)
      assert {:not_authorized, _} = result
      assert count == 0
    end
  end

  test "missing scopes fail closed", %{enrollment: enrollment} do
    assert {:not_authorized, _} = EnrollmentWriter.delete(enrollment, Authority.new(:school_admin, 1))
    assert Repo.get(Videdal.Enrollment, enrollment.id)
  end

  test "malformed relationship identifiers fail before querying", %{enrollment: enrollment, authority: authority} do
    {result, count} =
      count_queries(fn -> EnrollmentWriter.delete(%{enrollment | student_id: "invalid"}, authority) end)

    assert {:invalid, _} = result
    assert count == 0
  end

  test "soft delete authorizes relationships and retains lifecycle metadata", %{authority: authority} do
    student = insert(:student, school_id: authority.scopes.school_id)
    {result, count} = count_queries(fn -> StudentWriter.delete(student, authority) end)
    assert {:ok, deleted} = result
    refute is_nil(deleted.deleted_at)
    refute is_nil(Repo.get!(Videdal.Student, student.id).deleted_at)
    assert count == 4
    assert StudentWriter.__hawk_soft_delete__() == {:soft, :deleted_at}
  end

  test "soft delete and explicit hard delete deny inaccessible relationships", %{authority: authority} do
    student = insert(:student)

    for operation <- [:delete, :hard_delete] do
      {result, count} = count_queries(fn -> apply(StudentWriter, operation, [student, authority]) end)
      assert {:not_authorized, _} = result
      assert count == 1
      assert Repo.get!(Videdal.Student, student.id).deleted_at == nil
    end
  end

  test "soft_delete before the delete block retains soft deletion", %{authority: authority} do
    student = insert(:student, school_id: authority.scopes.school_id)
    assert {:ok, deleted} = SoftFirstWriter.delete(student, authority)
    refute is_nil(deleted.deleted_at)
    assert SoftFirstWriter.__hawk_soft_delete__() == {:soft, :deleted_at}
    assert {:not_authorized, _} = SoftFirstWriter.delete(insert(:student), authority)
  end

  test "restore retains its separate policy without running the delete block", %{authority: authority} do
    student = insert(:student, deleted_at: DateTime.utc_now(:second))
    {result, queries} = capture_queries(fn -> StudentWriter.restore(student, authority) end)
    assert {:ok, restored} = result
    assert restored.deleted_at == nil
    refute Enum.any?(queries, &String.starts_with?(&1, "SELECT TRUE"))
  end

  test "soft and hard deletion skip relationship queries for denied actors", %{student: student, authority: authority} do
    for operation <- [:delete, :hard_delete], actor <- [Authority.public(), Authority.readonly(authority)] do
      {result, count} = count_queries(fn -> apply(StudentWriter, operation, [student, actor]) end)
      assert {:not_authorized, _} = result
      assert count == 0
    end
  end

  test "delete blocks reject steps that can change reference identifiers" do
    for step <- ["cast([:school_id])", "defaults(school_id: nil)", "validate_required([:school_id])"] do
      source = """
      defmodule Hawk.DeleteRelationshipAuthorizationTest.InvalidWriter do
        use Hawk.Writer.Resource,
          model: Videdal.Student,
          repo: Videdal.Repo,
          policy: Videdal.Students.Policy
        create do
          cast([:name])
        end
        delete do
          #{step}
        end
      end
      """

      assert_raise ArgumentError, ~r/unsupported Hawk delete step/, fn -> Code.compile_string(source) end
    end
  end

  test "explicit hard delete checks relationships before persistence", %{authority: authority} do
    student = insert(:student, school_id: authority.scopes.school_id, deleted_at: DateTime.utc_now(:second))
    {result, count} = count_queries(fn -> StudentWriter.hard_delete(student, authority) end)
    assert {:ok, _} = result
    assert count == 4
    refute Repo.get(Videdal.Student, student.id)
  end
end
