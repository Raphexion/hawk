# Hawk

Hawk is a reusable Elixir library for building declarative JSON:API backends on
top of Ecto and PostgreSQL.

Hawk depends on Ecto, Ecto SQL, and Postgrex, but it does not define or supervise
a concrete `Ecto.Repo`. Applications provide their own Repo modules, database
configuration, migrations, and supervision tree.

## Golden path

A Hawk resource has four small modules plus optional web helpers:

- `Model` declares the Ecto schema and explicit JSON:API surface.
- `Policy` declares who can read/write.
- `Reader` owns filtering, sorting, pagination, and policy-aware preloads.
- `Writer` owns validation and mutations.
- JSON:API, OpenAPI, and LiveView helpers are generated from those declarations.

### Model

```elixir
defmodule MyApp.Course do
  use Hawk.Model

  model "courses" do
    field(:title, :string)
    belongs_to(:school, MyApp.School)
    belongs_to(:teacher, MyApp.Teacher)
    has_many(:grades, MyApp.Grade)
  end

  json_api do
    type("courses")
    doc("A course taught by a teacher at a school.")

    attribute(:title,
      doc: "Human-readable course title.",
      example: "Math"
    )

    relationship(:teacher,
      doc: "The teacher responsible for the course.",
      example: %{type: "teachers", id: "12"}
    )

    relationship(:grades,
      doc: "Grades awarded in this course.",
      example: [%{type: "grades", id: "1"}]
    )

    creatable([:title, :teacher])
    updatable([:title, :teacher])
  end
end
```

### Policy

```elixir
defmodule MyApp.Courses.Policy do
  use Hawk.Policy

  read do
    role(:system, :all)
    role(:public, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id, :teacher_id])
  end

  write(roles: [:school_admin])
end
```

`public` is anonymous readonly access. It is not system access and still goes
through the resource policy.

### Reader

```elixir
defmodule MyApp.Courses.Reader do
  use Hawk.Reader.Resource,
    repo: MyApp.Repo,
    schema: MyApp.Course,
    default_page_size: 100,
    max_page_size: 100

  filter(:id)
  filter(:school_id)
  filter(:teacher_id)

  sort(:id)
  sort(:title)

  preload(:teacher)
  preload(:grades)
end
```

Nested includes such as `include=grades.student` are turned into nested Ecto
preloads where every layer uses that resource's own reader and policy. Opening
`courses` does not accidentally open `grades` or `students`.

Readers apply `default_page_size` when the caller does not request a page size
and reject requests above `max_page_size`. Both default to `100` and can be
overridden per resource. Collection JSON:API responses include `meta.page` with
`size`, `number`, and returned `count`. Hawk accepts `page[size]` / `page[number]`
and the shorthand `page_size` / `page_number` query parameters.

### Writer

```elixir
defmodule MyApp.Courses.Writer do
  alias Hawk.{MutationContext, RepositoryBoundary, Writer}
  alias MyApp.{Course, Repo}
  alias MyApp.Courses.Policy

  def create(attrs, authority) do
    MutationContext.create(%Course{}, attrs, authority)
    |> Writer.cast([:title, :teacher_id])
    |> Writer.validate_required([:title, :teacher_id])
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end
end
```

### JSON:API controller

```elixir
defmodule MyAppWeb.CourseController do
  use Hawk.JsonApi.Controller,
    resource: MyApp.Courses,
    model: MyApp.Course,
    public: true
end
```

Generated actions:

- `index/2`
- `show/2`
- `create/2`
- `update/2`
- `delete/2`

Controller errors use JSON:API documents:

- invalid include/filter/sort/page: `400`
- authorization failure: `403`
- missing record: `404`
- validation failure: `422`

### OpenAPI controller

```elixir
defmodule MyAppWeb.OpenApiController do
  use Hawk.OpenApi.Controller,
    title: "My API",
    version: "1.0.0",
    resources: [MyApp.Course, MyApp.Grade]
end
```

This exposes `spec/0` and `show/2`. The specification is composed from Hawk
resource declarations: JSON:API schemas, request bodies, error documents, sort
parameters, pagination parameters, and valid include paths.

Frontend teams can generate TypeScript from that OpenAPI contract with their
preferred tooling, for example:

```bash
npx openapi-typescript http://localhost:4000/openapi.json -o src/api/types.ts
```

Hawk intentionally stays centered on the backend contract instead of owning a
frontend generator or client runtime.

### LiveView helpers

For simple single-resource pages:

```elixir
defmodule MyAppWeb.CourseIndexLive do
  use Hawk.LiveView,
    resource: MyApp.Courses,
    as: :course
end
```

This provides helpers such as `assign_index/3`, `assign_show/4`, and a default
`"hawk:delete"` event handler that routes mutations through the writer and maps
errors into LiveView-friendly assigns.

For richer workspace pages that coordinate related resources:

```elixir
defmodule MyAppWeb.CourseWorkspaceLive do
  use Hawk.LiveView.Page,
    resources: [
      course: [resource: MyApp.Courses],
      students: [resource: MyApp.Students],
      grades: [resource: MyApp.Grades]
    ]
end
```

Then load the page with per-resource read specs:

```elixir
CourseWorkspaceLive.assign_page(socket, authority,
  course: {:one, filter: %{id: course_id}, preloads: [:teacher]},
  students: {:all, filter: %{school_id: school_id}},
  grades: {:all, filter: %{course_id: course_id}, preloads: [:student]}
)
```

Each resource still goes through its own reader and policy. The page helper just
composes the reads and shared mutation events; it does not create a new bypass
around Hawk's authorization model.

### Resource contract test

```elixir
defmodule MyApp.CoursesContractTest do
  use Hawk.ResourceContractCase,
    resource: MyApp.Courses,
    model: MyApp.Course
end
```

The contract test checks that JSON:API attributes, relationships,
creatable/updatable fields, reader preloads, sorts, and filters agree with the
model and reader declarations.

### JSON:API controller contract test

```elixir
defmodule MyAppWeb.CoursesControllerTest do
  use Hawk.JsonApiControllerCase,
    controller: MyAppWeb.CoursesController,
    resource: MyApp.Courses,
    model: MyApp.Course,
    repo: MyApp.Repo

  authorities do
    %{
      school_admin: Hawk.Authority.new(:school_admin, 1, scopes: %{school_id: 7}),
      teacher: Hawk.Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})
    }
  end

  pre_sample authorities do
    %{
      school: %MyApp.School{id: 7},
      teacher: %MyApp.Teacher{id: authorities.teacher.identity, school_id: 7}
    }
  end

  sample _authorities, known, index do
    %MyApp.Course{
      id: index,
      title: "Course #{index}",
      school_id: known.school.id,
      teacher_id: known.teacher.id
    }
  end

  test "specific business rule still fits beside the generated matrix" do
    item_1 = generate_sample(1)
    item_2 = generate_sample(2)

    assert item_1.school_id == item_2.school_id
  end
end
```

The generated matrix exercises each configured authority against `index`,
paginated `index`, `show`, `create`, `update`, and `delete`. `:public` is always
included even when not listed in `authorities`, and its expected result comes
from the resource policy. Expected access is derived from the resource reader
and policy, while mutation payloads are built from JSON:API examples unless
`create_params` / `update_params` are supplied.

Controller cases define authorities and samples with small DSL blocks:

- `authorities do ... end` returns a map of named `Hawk.Authority` values. Hawk
  still adds `:public` automatically when omitted.
- `pre_sample(authorities) do ... end` optionally builds shared context once,
  such as parent records. The default returns `%{}`.
- `sample(authorities, known, index) do ... end` builds deterministic resource
  samples from the authorities and known context. This callback is required; if
  it is missing, Hawk raises a clear error explaining which function to add.

The matrix uses the generated samples for collection and pagination coverage,
and `sample_model()` — the first generated sample — for show/update/delete. The
default generated collection size is 3; only pass `sample_count:` when a
resource needs a larger collection.

Specific business-rule tests can call `generate_sample(index)` or
`generate_samples(count)` directly. These helpers reuse the same authorities,
`pre_sample`, and `sample` definitions as the generated matrix. `pre_sample` is
cached per test process, so it also works when it creates real PostgreSQL data
through fixtures or factories and several generated samples need to share those
records.

Applications should import Hawk's formatter settings so the DSL stays tidy:

```elixir
# .formatter.exs
[
  import_deps: [:hawk],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```
