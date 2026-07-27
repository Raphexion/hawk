defmodule Hawk.JsonApi.SchemaTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Schema

  # Schema is the shared dependency for Document and Request: it resolves the
  # external JSON:API shape of a resource (type, attributes, relationships,
  # writability) and maps external relationship names to schema associations.

  describe "metadata/2" do
    test "resolves adapter metadata from a Hawk.Resource facade" do
      assert Schema.metadata(Videdal.Course).type == "courses"
      assert Map.has_key?(Schema.metadata(Videdal.Course).attributes, :title)
    end

    test "resolves metadata from a struct" do
      assert Schema.metadata(%Videdal.Course{}).type == "courses"
    end
  end

  describe "schema_module/1" do
    test "extracts the struct module" do
      assert Schema.schema_module(%Videdal.Course{}) == Videdal.Course
    end
  end

  describe "relationship_mapping!/2" do
    test "returns the external name and schema source for a relationship" do
      {name, source} = Schema.relationship_mapping!(Schema.metadata(Videdal.Course), "teacher")
      assert name == :teacher
      assert source == :teacher
    end

    test "raises for unknown relationships" do
      assert_raise ArgumentError, ~r/unknown relationship "nope"/, fn ->
        Schema.relationship_mapping!(Schema.metadata(Videdal.Course), "nope")
      end
    end
  end

  describe "relationship_source!/2" do
    test "resolves a binary relationship name to its schema source" do
      assert Schema.relationship_source!(Schema.metadata(Videdal.Course), "teacher") == :teacher
    end

    test "resolves an atom relationship key to its schema source" do
      assert Schema.relationship_source!(Schema.metadata(Videdal.Course), :teacher) == :teacher
    end
  end

  describe "relationship_key!/3" do
    test "resolves a relationship name on a struct to its schema source" do
      assert Schema.relationship_key!(%Videdal.Course{}, "teacher") == :teacher
    end

    test "resolves a relationship name on a module to its schema source" do
      assert Schema.relationship_key!(Videdal.Course, "teacher") == :teacher
    end
  end

  describe "external_pointer/2" do
    test "maps a plain attribute to its external pointer" do
      assert Schema.external_pointer(Videdal.Course, :title) == "/data/attributes/title"
    end

    test "maps a source-renamed attribute to the external name a client sent" do
      # ExternalCourses declares attribute(:name, source: :title).
      assert Schema.external_pointer(Videdal.ExternalCourse, :title) ==
               "/data/attributes/name"
    end

    test "maps a belongs_to foreign key to the external relationship pointer" do
      # Grades: relationship(:course) is backed by belongs_to with owner_key :course_id.
      assert Schema.external_pointer(Videdal.Grade, :course_id) ==
               "/data/relationships/course"
    end

    test "falls back to the field name when it has no external surface" do
      # school_id is an internal-only column on Grade (no attribute, no relationship).
      assert Schema.external_pointer(Videdal.Grade, :school_id) ==
               "/data/attributes/school_id"
    end

    test "accepts a struct or a module" do
      assert Schema.external_pointer(%Videdal.ExternalCourse{}, :title) ==
               "/data/attributes/name"
    end
  end
end
