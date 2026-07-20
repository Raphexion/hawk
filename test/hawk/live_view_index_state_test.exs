defmodule Hawk.LiveView.IndexStateTest do
  use ExUnit.Case, async: true

  alias Hawk.LiveView.IndexState

  @live_view %{
    index: %{
      filters: [:teacher_id],
      searches: [%{name: :title, operator: :ilike}],
      sorts: [:id, :title]
    }
  }

  test "normalizes search, sort, and page params" do
    state =
      IndexState.normalize(
        %{
          "search" => %{"title" => "histo"},
          "sort" => "id",
          "page" => %{"number" => "3", "size" => "25"}
        },
        @live_view
      )

    assert state.filter == %{title: {:ilike, "%histo%"}}
    assert state.page == %{column: :id, dir: :asc, number: 3, size: 25}
    assert state.stream_reset? == true
  end

  test "page changes keep current search and sort" do
    current =
      IndexState.normalize(
        %{"search" => %{"title" => "histo"}, "sort" => "id"},
        @live_view
      )

    state = IndexState.normalize(%{"page" => %{"number" => "3"}}, @live_view, current)

    assert state.filter == %{title: {:ilike, "%histo%"}}
    assert state.page.column == :id
    assert state.page.dir == :asc
    assert state.page.number == 3
  end

  test "sort changes reset the page number" do
    current =
      IndexState.normalize(
        %{"search" => %{"title" => "histo"}, "sort" => "id", "page" => %{"number" => "3"}},
        @live_view
      )

    state = IndexState.normalize(%{"sort" => "-title"}, @live_view, current)

    assert state.filter == %{title: {:ilike, "%histo%"}}
    assert state.page == %{column: :title, dir: :desc, number: 1}
  end

  test "search changes reset the page number" do
    current =
      IndexState.normalize(
        %{"search" => %{"title" => "histo"}, "sort" => "id", "page" => %{"number" => "3"}},
        @live_view
      )

    state = IndexState.normalize(%{"search" => %{"title" => "math"}}, @live_view, current)

    assert state.filter == %{title: {:ilike, "%math%"}}
    assert state.page == %{column: :id, dir: :asc, number: 1}
  end

  test "clearing search removes that filter and resets the page number" do
    current =
      IndexState.normalize(
        %{"search" => %{"title" => "histo"}, "sort" => "id", "page" => %{"number" => "3"}},
        @live_view
      )

    state = IndexState.normalize(%{"search" => %{"title" => ""}}, @live_view, current)

    assert state.filter == :all
    assert state.page == %{column: :id, dir: :asc, number: 1}
  end

  test "unknown search keys are rejected without creating atoms" do
    hostile = "hawk_hostile_search_#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, "unknown LiveView search #{inspect(hostile)}", fn ->
      IndexState.normalize(%{"search" => %{hostile => "histo"}}, @live_view)
    end

    refute_existing_atom(hostile)
  end

  test "unknown sort keys are rejected without creating atoms" do
    hostile = "hawk_hostile_sort_#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, "unknown LiveView sort #{inspect(hostile)}", fn ->
      IndexState.normalize(%{"sort" => hostile}, @live_view)
    end

    refute_existing_atom(hostile)
  end

  defp refute_existing_atom(value) do
    _existing = String.to_existing_atom(value)
    flunk("expected #{inspect(value)} not to be an existing atom")
  rescue
    ArgumentError -> :ok
  end
end
