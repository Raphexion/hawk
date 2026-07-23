defmodule Hawk.Resource.ConventionTest do
  use ExUnit.Case, async: true

  alias Hawk.Resource.Convention

  describe "resource_module/1" do
    test "pluralizes a singular model name to its resource module" do
      assert Convention.resource_module(Videdal.Course) == Videdal.Courses
      assert Convention.resource_module(Videdal.School) == Videdal.Schools
      assert Convention.resource_module(Videdal.Teacher) == Videdal.Teachers
      assert Convention.resource_module(Videdal.Grade) == Videdal.Grades
    end

    test "handles ies pluralization (y after consonant)" do
      assert Convention.resource_module(Videdal.Policy) == Videdal.Policies
    end

    test "handles ses pluralization (sis suffix)" do
      # Analysis -> Analyses
      module = String.to_atom("Elixir.TestAnalysis")
      assert Convention.resource_module(module) == String.to_atom("Elixir.TestAnalyses")
    end

    test "handles es pluralization (s/x/z/ch/sh suffixes)" do
      # Box -> Boxes, Church -> Churches
      assert Convention.resource_module(String.to_atom("Elixir.TestBox")) ==
               String.to_atom("Elixir.TestBoxes")
      assert Convention.resource_module(String.to_atom("Elixir.TestChurch")) ==
               String.to_atom("Elixir.TestChurches")
    end

    test "collapses the namespace when the model is nested under its resource" do
      # MyApp.Courses.Course -> MyApp.Courses (not MyApp.Courses.Courses)
      module = String.to_atom("Elixir.MyApp.Courses.Course")
      assert Convention.resource_module(module) == String.to_atom("Elixir.MyApp.Courses")
    end
  end

  describe "policy_module/1 and reader_module/1" do
    test "derive the sibling policy and reader from a model by convention" do
      assert Convention.policy_module(Videdal.Course) == Videdal.Courses.Policy
      assert Convention.reader_module(Videdal.Course) == Videdal.Courses.Reader
    end
  end
end
