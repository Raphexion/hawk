defmodule Hawk do
  @moduledoc """
  An opinionated Phoenix backend foundation for resource-heavy systems.

  Hawk resources describe their persistence schema, JSON:API surface,
  authorization policy, reader behaviour, writer behaviour, optional custom
  actions, and source-backed queries in small sibling modules. Phoenix controllers, OpenAPI descriptions,
  LiveView helpers, and contract tests are generated from those declarations.

  Hawk does not define or supervise a concrete `Ecto.Repo`: host applications
  own their repo, database config, migrations, authentication, and supervision
  tree. Hawk owns the resource boundary — the reusable middle layer that makes
  the recurring backend/admin shape boring.

  ## Starting point

  `Hawk.Resource` is the entry point. A one-line facade ties together a model,
  reader, policy, writer, JSON:API adapter, and LiveView adapter:

      defmodule MyApp.Courses do
        use Hawk.Resource, model: MyApp.Course
      end

  From there, explore the DSL modules:

    * `Hawk.Model` — schema DSL and association resource metadata.
    * `Hawk.Reader.Resource` — filters, sorts, preloads.
    * `Hawk.Reader.FilterSet` — composable, independently testable filter groups.
    * `Hawk.Writer.Resource` — create/update/delete pipelines.
    * `Hawk.Policy` — read/write authorization.
    * `Hawk.Actions` — custom `/-actions/`.
    * `Hawk.Query` — policy-safe read-side derivations from source resources.
    * `Hawk.JsonApi.Resource` / `Hawk.LiveView.Resource` — the adapters.

  ## Tooling

    * `mix hawk.gen.resource` — scaffold a resource set from an Ecto schema.
    * `mix hawk.validate` — the authoritative contract-validation gate.
    * `mix hawk.openapi` — generate an OpenAPI spec from discovered resources.
    * `mix hawk.plans.spec` — generate the plan-operation manifest for AI-authored batches.

  See the README for the full golden path and `docs/` for the design notes.
  """
end
