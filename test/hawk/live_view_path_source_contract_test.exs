defmodule Hawk.LiveViewPathSourceContractTest do
  use ExUnit.Case, async: true

  Code.compile_string("""
  defmodule Hawk.PathSourceTest.Author do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "path_source_authors" do
      field(:name, :string)
    end
  end

  defmodule Hawk.PathSourceTest.Post do
    use Hawk.Model

    model "path_source_posts" do
      field(:title, :string)
      belongs_to(:author, Hawk.PathSourceTest.Author)
    end
  end
  """)


  test "a path source reaching an association the reader does not preload fails the contract" do
    assert_raise ArgumentError,
                 ~r/reaches association :author, which must be declared as a reader preload/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.PathSourceBad.Posts.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                     def preload_keys, do: MapSet.new([])
                   end

                   defmodule Hawk.PathSourceBad.Posts.Policy do
                     def read_filter(_authority), do: :all
                     def create?(_), do: true
                     def update?(_), do: true
                     def delete?(_), do: true
                   end

                   defmodule Hawk.PathSourceBad.Posts.Writer do
                     def create(_attrs, _authority), do: {:ok, %Hawk.PathSourceTest.Post{}}
                     def update(model, _attrs, _authority), do: {:ok, model}
                     def delete(model, _authority), do: {:ok, model}
                     def change_create(_attrs, _authority), do: %Ecto.Changeset{data: %Hawk.PathSourceTest.Post{}}
                     def change_update(_model, _attrs, _authority), do: %Ecto.Changeset{data: %Hawk.PathSourceTest.Post{}}
                   end

                   defmodule Hawk.PathSourceBad.Posts.JsonApi do
                     use Hawk.JsonApi.Resource
                     type("posts")
                     attribute(:title, writable: true)
                   end

                   defmodule Hawk.PathSourceBad.Posts.LiveView do
                     use Hawk.LiveView.Resource

                     as(:post)
                     plural_as(:posts)

                     index do
                       table do
                         column(:title)
                         column(:author_name, label: "Author", source: [:author, :name])
                       end
                     end
                   end

                   defmodule Hawk.PathSourceBad.Posts do
                     use Hawk.Resource, model: Hawk.PathSourceTest.Post
                   end
                   """)
                 end
  end

  test "a path source is accepted when the reader preloads the association" do
    Code.compile_string("""
    defmodule Hawk.PathSourceOk.Posts.Reader do
      def one(opts), do: {:one, opts}
      def all(opts), do: {:all, opts}
      def preload_keys, do: MapSet.new([:author])
    end

    defmodule Hawk.PathSourceOk.Posts.Policy do
      def read_filter(_authority), do: :all
      def create?(_), do: true
      def update?(_), do: true
      def delete?(_), do: true
    end

    defmodule Hawk.PathSourceOk.Posts.Writer do
      def create(_attrs, _authority), do: {:ok, %Hawk.PathSourceTest.Post{}}
      def update(model, _attrs, _authority), do: {:ok, model}
      def delete(model, _authority), do: {:ok, model}
      def change_create(_attrs, _authority), do: %Ecto.Changeset{data: %Hawk.PathSourceTest.Post{}}
      def change_update(_model, _attrs, _authority), do: %Ecto.Changeset{data: %Hawk.PathSourceTest.Post{}}
    end

    defmodule Hawk.PathSourceOk.Posts.JsonApi do
      use Hawk.JsonApi.Resource
      type("posts")
      attribute(:title, writable: true)
    end

    defmodule Hawk.PathSourceOk.Posts.LiveView do
      use Hawk.LiveView.Resource

      as(:post)
      plural_as(:posts)

      index do
        table do
          column(:title)
          column(:author_name, label: "Author", source: [:author, :name])
        end
      end

      show do
        field(:author_name, label: "Author", source: [:author, :name])
      end
    end

    defmodule Hawk.PathSourceOk.Posts do
      use Hawk.Resource, model: Hawk.PathSourceTest.Post
    end
    """)

    assert function_exported?(Hawk.PathSourceOk.Posts, :one, 1)
  end

  test "a path source on a form field is rejected (forms bind to root attrs)" do
    assert_raise ArgumentError,
                 ~r/create_form field :author_name uses a path source :author; form fields bind to root-model attrs/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.PathSourceForm.Posts.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                     def preload_keys, do: MapSet.new([:author])
                   end

                   defmodule Hawk.PathSourceForm.Posts.Policy do
                     def read_filter(_authority), do: :all
                     def create?(_), do: true
                     def update?(_), do: true
                     def delete?(_), do: true
                   end

                   defmodule Hawk.PathSourceForm.Posts.Writer do
                     def create(_attrs, _authority), do: {:ok, %Hawk.PathSourceTest.Post{}}
                     def update(model, _attrs, _authority), do: {:ok, model}
                     def delete(model, _authority), do: {:ok, model}
                     def change_create(_attrs, _authority), do: %Ecto.Changeset{data: %Hawk.PathSourceTest.Post{}}
                     def change_update(_model, _attrs, _authority), do: %Ecto.Changeset{data: %Hawk.PathSourceTest.Post{}}
                   end

                   defmodule Hawk.PathSourceForm.Posts.JsonApi do
                     use Hawk.JsonApi.Resource
                     type("posts")
                     attribute(:title, writable: true)
                   end

                   defmodule Hawk.PathSourceForm.Posts.LiveView do
                     use Hawk.LiveView.Resource

                     as(:post)
                     plural_as(:posts)

                     create_form do
                       field(:title)
                       field(:author_name, label: "Author", source: [:author, :name])
                     end
                   end

                   defmodule Hawk.PathSourceForm.Posts do
                     use Hawk.Resource, model: Hawk.PathSourceTest.Post
                   end
                   """)
                 end
  end

  test "a nested association the nested reader does not preload fails the contract" do
    # Grades.Reader preloads :student, but Students.Reader does not preload :grades.
    # A path [:student, :grades, :score] on a Grades-backed LiveView should fail:
    # :student is preloaded by the root reader, but :grades on Student is NOT
    # preloaded by Students.Reader — the contract must catch this at depth > 1.
    assert_raise ArgumentError,
                 ~r/reaches nested association :grades on Videdal.Student, which must be declared as a reader preload by Videdal.Students.Reader/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.PathSourceNested.Posts.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                     def preload_keys, do: MapSet.new([:student])
                   end

                   defmodule Hawk.PathSourceNested.Posts.Policy do
                     def read_filter(_authority), do: :all
                     def create?(_), do: true
                     def update?(_), do: true
                     def delete?(_), do: true
                   end

                   defmodule Hawk.PathSourceNested.Posts.Writer do
                     def create(_attrs, _authority), do: {:ok, %Videdal.Grade{}}
                     def update(model, _attrs, _authority), do: {:ok, model}
                     def delete(model, _authority), do: {:ok, model}
                     def change_create(_attrs, _authority), do: %Ecto.Changeset{data: %Videdal.Grade{}}
                     def change_update(_model, _attrs, _authority), do: %Ecto.Changeset{data: %Videdal.Grade{}}
                   end

                   defmodule Hawk.PathSourceNested.Posts.JsonApi do
                     use Hawk.JsonApi.Resource
                     type("grades")
                     attribute(:score, writable: true)
                   end

                   defmodule Hawk.PathSourceNested.Posts.LiveView do
                     use Hawk.LiveView.Resource

                     as(:post)
                     plural_as(:posts)

                     index do
                       table do
                         column(:score)
                         column(:student_grades, label: "Student grades", source: [:student, :grades, :score])
                       end
                     end
                   end

                   defmodule Hawk.PathSourceNested.Posts do
                     use Hawk.Resource, model: Videdal.Grade
                   end
                   """)
                 end
  end
end
