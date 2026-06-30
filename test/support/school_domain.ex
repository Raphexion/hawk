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
