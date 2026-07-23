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

    test "honors the json_api_by_model override" do
      override = %{type: "overridden", attributes: %{}, relationships: %{}, creatable: [], updatable: []}
      assert Schema.metadata(Videdal.Course, json_api_by_model: %{Videdal.Course => override}).type ==
               "overridden"
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
end
