defmodule Videdal.ExternalCourses.Writer do
  @moduledoc false

  def create(attrs, _authority) do
    Process.put({__MODULE__, :create_attrs}, attrs)

    {:ok,
     %Videdal.ExternalCourse{
       id: Videdal.course_id(),
       title: Map.fetch!(attrs, :title),
       public_slug: Map.fetch!(attrs, :public_slug),
       teacher_id: Map.fetch!(attrs, :teacher_id)
     }}
  end

  def update(%Videdal.ExternalCourse{} = model, attrs, _authority) do
    Process.put({__MODULE__, :update_attrs}, attrs)

    {:ok,
     %Videdal.ExternalCourse{
       model
       | title: Map.get(attrs, :title, model.title),
         public_slug: Map.get(attrs, :public_slug, model.public_slug),
         teacher_id: Map.get(attrs, :teacher_id, model.teacher_id)
     }}
  end

  def delete(model, _authority), do: {:ok, model}
end
