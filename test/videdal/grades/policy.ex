defmodule Videdal.Grades.Policy do
  @moduledoc """
  Authorization policy for the Videdal `Grades` resource.

  Grades intentionally pressure-test Hawk read policy because visibility crosses
  several relationship paths: teachers through courses, students directly, and
  parents through the parent/student link table.
  """

  alias Hawk.Authority
  alias Videdal.PolicySupport

  def read_filter(%Authority{} = authority) do
    cond do
      PolicySupport.unrestricted_read?(authority) ->
        :all

      authority.role == :school_admin ->
        PolicySupport.scoped_filter(authority, [:school_id])

      authority.role == :teacher ->
        PolicySupport.scoped_filter(authority, [:school_id, :teacher_id])

      authority.role == :student ->
        PolicySupport.scoped_filter(authority, [:school_id, :student_id])

      authority.role == :parent ->
        PolicySupport.scoped_filter(authority, [:school_id, :parent_id])

      true ->
        :none
    end
  end
end
