defmodule Hawk.Plan do
  @moduledoc """
  A closed-form plan: a sequence of resource-shaped operations an AI authors
  and a human reviews before execution.

  The plan is pure data — serializable to JSON, no storage. The host app stores
  it however it likes (its own table, its own migration, its own policy). Hawk
  owns the plan *struct* and the *execution invariants*; the host app owns plan
  *storage* and *plan-lifecycle auth*.

  ## Plan ops

  Each op is one of:

    * `{op: :create, resource: "courses", attrs: %{...}, relationships: %{...}}`
    * `{op: :update, resource: "courses", id: "crs-math", attrs: %{...}}`
    * `{op: :delete, resource: "enrollments", id: "enr-ada-math"}`
    * `{op: :action, resource: "courses", id: "crs-math", action: "close-registration", params: %{...}}`

  Plus optional `comment:` fields per op — the AI's narrative. The executor
  never reads them; the review surface renders them as prose.
  """

  defstruct ops: [], comments: %{}, authoring_authority: nil

  @type op :: map()
  @type t :: %__MODULE__{
          ops: [op()],
          comments: map(),
          authoring_authority: Hawk.Authority.t() | nil
        }

  @doc """
  Builds a plan from a list of ops.
  """
  @spec new([op()], keyword()) :: t()
  def new(ops, opts \\ []) when is_list(ops) and is_list(opts) do
    %__MODULE__{
      ops: ops,
      comments: Keyword.get(opts, :comments, %{}),
      authoring_authority: Keyword.get(opts, :authoring_authority)
    }
  end
end
