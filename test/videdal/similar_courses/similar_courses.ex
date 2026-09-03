defmodule Videdal.SimilarCourses do
  @moduledoc """
  Videdal fixture query used to exercise Hawk.Query declaration metadata.
  """

  use Hawk.Query,
    name: :similar_courses,
    source: Videdal.Courses,
    transaction: true,
    pagination: :offset

  filter(:school_id)
  filter(:title)

  rank(:title_similarity, sort: [asc: :title], tie_breaker: :id)

  @impl Hawk.Query
  def cast_params(%{"raise" => true}) do
    raise "cast_params must not run after query-policy denial"
  end

  def cast_params(%{"invalid" => "true"}) do
    {:error, Hawk.Error.bad_request("invalid similar course query")}
  end

  def cast_params(params), do: {:ok, params}

  @impl Hawk.Query
  def prepare(_repo, %{"fail_prepare" => "true"}, _context) do
    {:error, Hawk.Error.bad_request("prepare failed")}
  end

  def prepare(repo, %{"notify_prepare" => "true"}, %{test_pid: test_pid}) do
    send(test_pid, {:prepared, repo})
    :ok
  end

  def prepare(_repo, _params, _context), do: :ok
end
