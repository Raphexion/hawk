defmodule Videdal.PreparedSimilarCourses.Policy do
  use Hawk.Policy

  @moduledoc false

  read(:all)
end

defmodule Videdal.PreparedSimilarCourses do
  @moduledoc false

  use Hawk.Query,
    name: :prepared_similar_courses,
    source: Videdal.PreparedCourses,
    transaction: true,
    pagination: :offset

  filter(:prepared_marker)
  rank(:title_similarity, sort: [asc: :title], tie_breaker: :id)

  @impl Hawk.Query
  def prepare(repo, %{"set_marker" => marker}, _context) do
    repo.query!("SELECT set_config('hawk.similar_courses.marker', $1, true)", [marker])
    :ok
  end

  def prepare(_repo, _params, _context), do: :ok
end
