defmodule Hawk.QueryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "valid query exports inspectable metadata" do
    assert Videdal.SimilarCourses.__hawk_query__(:name) == :similar_courses
    assert Videdal.SimilarCourses.__hawk_query__(:source) == Videdal.Courses
    assert Videdal.SimilarCourses.__hawk_query__(:policy) == Videdal.SimilarCourses.Policy
    assert Videdal.SimilarCourses.__hawk_query__(:transaction) == true
    assert Videdal.SimilarCourses.__hawk_query__(:pagination) == :offset

    assert Videdal.SimilarCourses.__hawk_query__(:filter_keys) == MapSet.new([:school_id, :title])

    assert Videdal.SimilarCourses.__hawk_query__(:source_filters) == %{
             school_id: :school_id,
             title: :title
           }

    assert Videdal.SimilarCourses.__hawk_query__(:query_params) == %{
             source_course_id: %{required: false, source_filter: :similar_to_course_id}
           }

    assert Videdal.SimilarCourses.__hawk_query__(:rank) == %{
             name: :title_similarity,
             sort: [asc: :title, asc: :id],
             source_scope: nil,
             tie_breaker: :id
           }

    assert function_exported?(Videdal.SimilarCourses, :page, 1)
    refute function_exported?(Videdal.SimilarCourses, :all, 1)
    refute function_exported?(Videdal.SimilarCourses, :count, 1)
  end

  test "valid query metadata is available as one map" do
    assert %{
             name: :similar_courses,
             module: Videdal.SimilarCourses,
             source: Videdal.Courses,
             policy: Videdal.SimilarCourses.Policy,
             transaction: true,
             pagination: :offset,
             filter_keys: filter_keys,
             source_filters: %{school_id: :school_id, title: :title},
             query_params: %{source_course_id: %{required: false, source_filter: :similar_to_course_id}},
             rank: %{name: :title_similarity, sort: [asc: :title, asc: :id], source_scope: nil, tie_breaker: :id}
           } = Hawk.Query.metadata(Videdal.SimilarCourses)

    assert filter_keys == MapSet.new([:school_id, :title])
  end

  test "invalid local declaration fails" do
    assert_raise ArgumentError, ~r/Hawk query :name must be a non-empty atom/, fn ->
      Code.compile_string("""
      defmodule Hawk.QueryTest.InvalidName do
        use Hawk.Query, name: \"bad\", source: Videdal.Courses
      end
      """)
    end
  end

  test "source must be a resource facade" do
    assert_raise ArgumentError, ~r/Hawk query :source Videdal.Course must be a Hawk.Resource facade/, fn ->
      Code.compile_string("""
      defmodule Hawk.QueryTest.InvalidSource do
        use Hawk.Query, name: :invalid_source, source: Videdal.Course
      end
      """)
    end
  end

  test "missing policy warns in compile mode" do
    warning =
      capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule Hawk.QueryTest.MissingPolicy do
          use Hawk.Query, name: :missing_policy, source: Videdal.Courses
        end
        """)
      end)

    assert warning =~ "Hawk query policy module Hawk.QueryTest.MissingPolicy.Policy is not available yet"
  end

  test "malformed policy fails immediately" do
    assert_raise ArgumentError,
                 ~r/Hawk query policy module Hawk.QueryTest.MalformedPolicy.Policy must define read_filter\/1/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.QueryTest.MalformedPolicy.Policy do
                   end

                   defmodule Hawk.QueryTest.MalformedPolicy do
                     use Hawk.Query, name: :malformed_policy, source: Videdal.Courses
                   end
                   """)
                 end
  end

  test "duplicate query filters fail at compile time" do
    assert_raise ArgumentError, ~r/duplicate Hawk query filter :school_id/, fn ->
      Code.compile_string("""
      defmodule Hawk.QueryTest.DuplicateFilter do
        use Hawk.Query, name: :duplicate_filter, source: Videdal.Courses
        filter(:school_id)
        filter(:school_id)
      end
      """)
    end
  end

  test "query filters must map to source reader filters in strict mode" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.UnknownSourceFilter.Policy do
      use Hawk.Policy
      read(:all)
    end

    defmodule Hawk.QueryTest.UnknownSourceFilter do
      use Hawk.Query, name: :unknown_source_filter, source: Videdal.Courses
      filter(:topic_id)
    end
    """)

    assert_raise ArgumentError,
                 ~r/filter :topic_id maps to source filter :topic_id, which is not declared by Videdal.Courses/,
                 fn ->
                   Hawk.Query.validate!(Hawk.QueryTest.UnknownSourceFilter, :strict)
                 end
  end

  test "policy keys must map to declared query filters in strict mode" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.UnmappedPolicy.Policy do
      use Hawk.Policy

      read do
        role(:school_admin, scopes: [:teacher_id])
      end
    end

    defmodule Hawk.QueryTest.UnmappedPolicy do
      use Hawk.Query, name: :unmapped_policy, source: Videdal.Courses
      filter(:school_id)
    end
    """)

    assert_raise ArgumentError,
                 ~r/read filter :teacher_id must map to a declared query filter/,
                 fn ->
                   Hawk.Query.validate!(Hawk.QueryTest.UnmappedPolicy, :strict)
                 end
  end

  test "missing policy fails in strict mode" do
    capture_io(:stderr, fn ->
      Code.compile_string("""
      defmodule Hawk.QueryTest.StrictMissingPolicy do
        use Hawk.Query, name: :strict_missing_policy, source: Videdal.Courses
      end
      """)
    end)

    assert_raise ArgumentError,
                 ~r/Hawk query policy module Hawk.QueryTest.StrictMissingPolicy.Policy is not available/,
                 fn ->
                   Hawk.Query.validate!(Hawk.QueryTest.StrictMissingPolicy, :strict)
                 end
  end

  test "query param mappings must be source reader filters in strict mode" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.UnknownQueryParamSourceFilter.Policy do
      use Hawk.Policy

      read(:all)
    end

    defmodule Hawk.QueryTest.UnknownQueryParamSourceFilter do
      use Hawk.Query, name: :unknown_query_param_source_filter, source: Videdal.Courses

      query_param(:source_course_id, source_filter: :missing_source_filter)
    end
    """)

    assert_raise ArgumentError,
                 ~r/query param :source_course_id maps to source filter :missing_source_filter/,
                 fn ->
                   Hawk.Query.validate!(Hawk.QueryTest.UnknownQueryParamSourceFilter, :strict)
                 end
  end

  test "duplicate query params are rejected" do
    assert_raise ArgumentError, ~r/duplicate Hawk query param :source_course_id/, fn ->
      Code.compile_string("""
      defmodule Hawk.QueryTest.DuplicateQueryParam.Policy do
        use Hawk.Policy

        read(:all)
      end

      defmodule Hawk.QueryTest.DuplicateQueryParam do
        use Hawk.Query, name: :duplicate_query_param, source: Videdal.Courses

        query_param(:source_course_id)
        query_param(:source_course_id)
      end
      """)
    end
  end

  test "query params can opt out of source filter mapping" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.UnmappedQueryParam.Policy do
      use Hawk.Policy

      read(:all)
    end

    defmodule Hawk.QueryTest.UnmappedQueryParam do
      use Hawk.Query, name: :unmapped_query_param, source: Videdal.Courses

      query_param(:target_waitlist_count, required: true, source_filter: false)
    end
    """)

    assert Hawk.Query.validate!(Hawk.QueryTest.UnmappedQueryParam, :strict) == :ok

    assert Hawk.QueryTest.UnmappedQueryParam.__hawk_query__(:query_params) == %{
             target_waitlist_count: %{required: true, source_filter: false}
           }
  end

  test "rank requires a deterministic tie breaker" do
    assert_raise ArgumentError, ~r/Hawk query rank :similarity requires :tie_breaker/, fn ->
      Code.compile_string("""
      defmodule Hawk.QueryTest.RankWithoutTieBreaker.Policy do
        use Hawk.Policy
        read(:all)
      end

      defmodule Hawk.QueryTest.RankWithoutTieBreaker do
        use Hawk.Query, name: :rank_without_tie_breaker, source: Videdal.Courses
        rank(:similarity, sort: [asc: :title])
      end
      """)
    end
  end

  test "only one rank is supported" do
    assert_raise ArgumentError, ~r/Hawk query declares multiple ranks/, fn ->
      Code.compile_string("""
      defmodule Hawk.QueryTest.MultipleRanks.Policy do
        use Hawk.Policy
        read(:all)
      end

      defmodule Hawk.QueryTest.MultipleRanks do
        use Hawk.Query, name: :multiple_ranks, source: Videdal.Courses
        rank(:first, sort: [asc: :title], tie_breaker: :id)
        rank(:second, sort: [asc: :id], tie_breaker: :id)
      end
      """)
    end
  end

  test "rank tie breaker can use a renamed source resource identity" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.RosterRank.Policy do
      use Hawk.Policy
      read(:all)
    end

    defmodule Hawk.QueryTest.RosterRank do
      use Hawk.Query, name: :roster_rank, source: Videdal.CourseRosters
      rank(:course_order, sort: [asc: :course_id], tie_breaker: :course_id)
    end
    """)

    query = Module.concat(Hawk.QueryTest, RosterRank)

    assert Hawk.Query.validate!(query, :strict) == :ok
    assert apply(query, :__hawk_query__, [:rank]).sort == [asc: :course_id]
  end

  test "rank tie breaker must be the source resource identity in strict mode" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.NonIdentityTieBreaker.Policy do
      use Hawk.Policy
      read(:all)
    end

    defmodule Hawk.QueryTest.NonIdentityTieBreaker do
      use Hawk.Query, name: :non_identity_tie_breaker, source: Videdal.Courses
      rank(:similarity, sort: [asc: :title], tie_breaker: :title)
    end
    """)

    assert_raise ArgumentError,
                 ~r/rank :similarity tie breaker :title must be the source resource identity :id/,
                 fn ->
                   Hawk.Query.validate!(Hawk.QueryTest.NonIdentityTieBreaker, :strict)
                 end
  end

  test "rank source scope must be declared by source reader in strict mode" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.UnknownRankSourceScope.Policy do
      use Hawk.Policy
      read(:all)
    end

    defmodule Hawk.QueryTest.UnknownRankSourceScope do
      use Hawk.Query, name: :unknown_rank_source_scope, source: Videdal.Courses
      rank(:similarity, source_scope: :missing_rank_scope, tie_breaker: :id)
    end
    """)

    assert_raise ArgumentError,
                 ~r/rank :similarity source scope :missing_rank_scope must be declared by source reader/,
                 fn ->
                   Hawk.Query.validate!(Hawk.QueryTest.UnknownRankSourceScope, :strict)
                 end
  end

  test "rank must use either sort or source_scope" do
    assert_raise ArgumentError, ~r/rank :similarity must declare exactly one of :sort or :source_scope/, fn ->
      Code.compile_string("""
      defmodule Hawk.QueryTest.MixedRank.Policy do
        use Hawk.Policy
        read(:all)
      end

      defmodule Hawk.QueryTest.MixedRank do
        use Hawk.Query, name: :mixed_rank, source: Videdal.Courses
        rank(:similarity, sort: [asc: :title], source_scope: :largest_waitlist, tie_breaker: :id)
      end
      """)
    end
  end

  test "rank sort keys must be source reader sorts in strict mode" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.UnknownRankSort.Policy do
      use Hawk.Policy
      read(:all)
    end

    defmodule Hawk.QueryTest.UnknownRankSort do
      use Hawk.Query, name: :unknown_rank_sort, source: Videdal.Courses
      rank(:similarity, sort: [asc: :teacher_id], tie_breaker: :id)
    end
    """)

    assert_raise ArgumentError,
                 ~r/rank :similarity sort key :teacher_id must be declared by source reader/,
                 fn ->
                   Hawk.Query.validate!(Hawk.QueryTest.UnknownRankSort, :strict)
                 end
  end

  test "prepare requires transaction true in strict mode" do
    Code.compile_string("""
    defmodule Hawk.QueryTest.PrepareWithoutTransaction.Policy do
      use Hawk.Policy
      read(:all)
    end

    defmodule Hawk.QueryTest.PrepareWithoutTransaction do
      use Hawk.Query, name: :prepare_without_transaction, source: Videdal.Courses

      def prepare(_repo, _params, _context), do: :ok
    end
    """)

    assert_raise ArgumentError,
                 ~r/defines prepare\/3 but did not declare transaction: true/,
                 fn ->
                   Hawk.Query.validate!(Hawk.QueryTest.PrepareWithoutTransaction, :strict)
                 end
  end
end
