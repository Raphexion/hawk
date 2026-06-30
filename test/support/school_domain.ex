defmodule Hawk.TestSupport.School do
  @moduledoc false

  @reader_filter_keys MapSet.new([
                        :id,
                        :school_id,
                        :student_id,
                        :teacher_id,
                        :course_id,
                        :active,
                        :enrolled_on_or_after
                      ])

  def reader_filter_keys, do: @reader_filter_keys
end

defmodule Hawk.TestSupport.School.Policy do
  @moduledoc false

  alias Hawk.Authority

  def read_filter(%Authority{} = authority) do
    cond do
      Authority.system?(authority) ->
        :all

      authority.role == :principal ->
        :all

      authority.role == :school_admin ->
        scoped_filter(authority, [:school_id])

      authority.role == :teacher ->
        scoped_filter(authority, [:school_id, :teacher_id])

      authority.role == :student ->
        scoped_filter(authority, [:school_id, :student_id], %{active: true})

      true ->
        :none
    end
  end

  defp scoped_filter(authority, required_scopes, extra_filter \\ %{}) do
    Enum.reduce_while(required_scopes, extra_filter, fn scope, filter ->
      case Authority.fetch_scope(authority, scope) do
        {:ok, value} -> {:cont, Map.put(filter, scope, value)}
        :error -> {:halt, :none}
      end
    end)
  end
end

defmodule Hawk.TestSupport.School.School do
  @moduledoc false

  use Ecto.Schema

  schema "schools" do
    field(:name, :string)
  end
end

defmodule Hawk.TestSupport.School.Teacher do
  @moduledoc false

  use Ecto.Schema

  schema "teachers" do
    field(:name, :string)
    belongs_to(:school, Hawk.TestSupport.School.School)
  end
end

defmodule Hawk.TestSupport.School.Student do
  @moduledoc false

  use Ecto.Schema

  schema "students" do
    field(:name, :string)
    field(:active, :boolean, default: true)
    belongs_to(:school, Hawk.TestSupport.School.School)
  end
end

defmodule Hawk.TestSupport.School.Course do
  @moduledoc false

  use Ecto.Schema

  schema "courses" do
    field(:title, :string)
    belongs_to(:school, Hawk.TestSupport.School.School)
    belongs_to(:teacher, Hawk.TestSupport.School.Teacher)
  end
end

defmodule Hawk.TestSupport.School.Enrollment do
  @moduledoc false

  use Ecto.Schema

  schema "enrollments" do
    field(:enrolled_on, :date)
    belongs_to(:school, Hawk.TestSupport.School.School)
    belongs_to(:student, Hawk.TestSupport.School.Student)
    belongs_to(:course, Hawk.TestSupport.School.Course)
  end
end
