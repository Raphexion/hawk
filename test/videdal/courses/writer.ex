defmodule Videdal.Courses.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Courses` resource.
  """

  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.Repo,
    policy: Videdal.Courses.Policy

  create do
    cast([:title, :school_id, :teacher_id])
    validate_required([:title, :school_id, :teacher_id])
    validate(&reject_reserved_title/1)
  end

  update do
    cast([:title, :school_id, :teacher_id])
    validate(&reject_reserved_title/1)
  end

  defp reject_reserved_title(context) do
    case Ecto.Changeset.get_change(context.changeset, :title) do
      "Forbidden" -> {:error, :title, "is reserved"}
      _title -> :ok
    end
  end

  delete(:default)
end
