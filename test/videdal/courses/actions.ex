defmodule Videdal.Courses.Actions do
  @moduledoc """
  Custom JSON:API actions for Videdal courses.
  """

  use Hawk.Actions

  import Ecto.Query

  alias Ecto.Changeset
  alias Hawk.{MutationContext, RepositoryBoundary, Result, Writer}
  alias Videdal.{Course, Enrollment, Repo}
  alias Videdal.Courses.Policy

  action("open-registration",
    doc: "Open course registration and configure seats and waitlist capacity.",
    params: [
      seat_count: [
        type: :integer,
        doc: "Seats offered immediately when registration opens.",
        example: 2
      ],
      waitlist_count: [
        type: :integer,
        doc: "How many waitlist places should be tracked for this course.",
        example: 1
      ]
    ]
  )

  action("close-registration",
    doc: "Close registration and finalize each student as enrolled, waitlisted, or rejected.",
    params: []
  )

  def open_registration(%Course{} = course, params, authority) do
    MutationContext.update(course, Map.put(params, :registration_state, "open"), authority)
    |> Writer.cast([:registration_state, :seat_count, :waitlist_count])
    |> Writer.validate_required([:seat_count, :waitlist_count])
    |> Writer.validate_changeset(&validate_registration_counts/1)
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def close_registration(%Course{} = course, params, authority) do
    context =
      MutationContext.update(course, params, authority)
      |> Writer.validate(fn context ->
        if context.model.registration_state == "open" do
          :ok
        else
          {:error, :registration_state, "must be open before it can be closed"}
        end
      end)
      |> MutationContext.validate_policy(&Policy.update?/1)

    case context.error do
      :none -> finalize_registration(context)
      :invalid -> {:invalid, context}
      :not_authorized -> {:not_authorized, context}
    end
  end

  defp finalize_registration(context) do
    Repo.transaction(fn ->
      enrollments = list_enrollments(context.model.id)

      with :ok <- update_enrollments(enrollments, context.model),
           {:ok, course} <- close_course(context) do
        {:ok, course}
      else
        {:error, %Changeset{} = changeset} ->
          {:invalid, %{context | changeset: changeset, error: :invalid}}

        {:error, message} when is_binary(message) ->
          Result.error(message)

        other ->
          other
      end
    end)
    |> unwrap_transaction()
  end

  defp list_enrollments(course_id) do
    from(enrollment in Enrollment,
      where: enrollment.course_id == ^course_id,
      order_by: [asc: enrollment.enrolled_on, asc: enrollment.id]
    )
    |> Repo.all()
  end

  defp update_enrollments(enrollments, course) do
    enrollments
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {enrollment, index}, :ok ->
      status = enrollment_status(index, course)

      enrollment
      |> Changeset.change(%{registration_status: status})
      |> Repo.update()
      |> case do
        {:ok, _enrollment} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp close_course(context) do
    MutationContext.update(context.model, %{registration_state: "closed"}, context.authority)
    |> Writer.cast([:registration_state])
    |> MutationContext.mark_policy_validated()
    |> RepositoryBoundary.update(Repo)
  end

  defp enrollment_status(index, course) do
    cond do
      index < course.seat_count -> "enrolled"
      index < course.seat_count + course.waitlist_count -> "waitlisted"
      true -> "rejected"
    end
  end

  defp validate_registration_counts(changeset) do
    changeset
    |> Changeset.validate_number(:seat_count, greater_than_or_equal_to: 0)
    |> Changeset.validate_number(:waitlist_count, greater_than_or_equal_to: 0)
  end

  defp unwrap_transaction({:ok, result}), do: result

  # Two-phase action: create a grade and rename the course in one transaction.
  # `build: true` opts into the generated `submit_grade_change/3` (validate)
  # and `submit_grade_run/3` (commit), both projected from `build_submit_grade/3`.

  alias Videdal.{Courses, Grades}

  action("submit-grade",
    doc: "Create a grade and rename the course in one transaction.",
    build: true,
    params: [
      score: [type: :integer, doc: "Numeric grade.", example: 7],
      student_id: [type: :string, doc: "Student receiving the grade."]
    ]
  )

  def build_submit_grade(%Videdal.Course{} = course, params, authority) do
    Hawk.Multi.new()
    |> Hawk.Multi.create(
      :grade,
      Grades,
      %{score: params.score, student_id: params.student_id, course_id: course.id, school_id: course.school_id},
      authority
    )
    |> Hawk.Multi.update(:course, Courses, course, %{title: course.title <> " (graded)"}, authority)
  end
end
