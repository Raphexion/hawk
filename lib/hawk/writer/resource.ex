defmodule Hawk.Writer.Resource do
  @moduledoc """
  The declarative writer DSL for a Hawk resource: `create`, `update`, `delete`,
  and DB `constraint` steps.

  The DSL generates paired form and persistence functions from the *same*
  mutation pipeline, so JSON:API writes and LiveView live validation cannot
  drift: `change_create/2` / `change_update/3` build the changeset used for form
  validation, and `create/2` / `update/3` / `delete/2` persist through the same
  pipeline plus the repository boundary.

  Every mutation goes through the resource `Policy` (create?/update?/delete?)
  before touching the repo.

  ## Options

    * `:model` (required) — the `Hawk.Model` / `Ecto.Schema` to mutate.
    * `:repo` (required) — the `Ecto.Repo` to persist through.
    * `:policy` (required) — the `Hawk.Policy` module gating writes.
    * `:pubsub` — the host application's `Phoenix.PubSub` module. When set,
      every successful `create/update/delete` broadcasts a `Hawk.PubSub.Event`
      so LiveViews (and other subscribers) can refresh without reloading. Omit
      for no broadcast. See `Hawk.PubSub`.
    * `:topics` — a `Hawk.PubSub.TopicStrategy` module deriving the PubSub
      topics (optional; defaults to `Hawk.PubSub.DefaultTopics`). The default
      broadcasts to the shared resource topic and the instance topic. Pass an
      app module for tenant/owner isolation — see `Hawk.PubSub.TopicStrategy`.

  ## DSL

  Inside `create` and `update` blocks:

    * `cast([:field, ...])` — cast fields onto the changeset.
    * `defaults(field: value, ...)` — apply defaults before casting.
    * `validate_required([:field, ...])` — required-field validation.
    * `validate(&fun/1)` — run a validator that returns a changeset.
    * `validate_changeset(&fun/1)` — run a function receiving the changeset.
    * `constraint(kind, field, opts)` — declare a DB constraint (see `constraint/3`).

  `delete(:default)` enables the standard delete through the policy.

  ## Example

      defmodule MyApp.Courses.Writer do
        use Hawk.Writer.Resource,
          model: MyApp.Course,
          repo: MyApp.Repo,
          policy: MyApp.Courses.Policy

        create do
          defaults(registration_state: "draft")
          cast([:title, :teacher_id, :registration_state])
          validate_required([:title, :teacher_id])
          validate(&reject_reserved_title/1)
          constraint(:foreign_key, :teacher_id, name: :courses_teacher_id_fkey)
        end

        update do
          cast([:title, :registration_state])
          validate_required([:title])
        end

        delete(:default)
      end

  ## Generated functions

    * `change_create/2`, `change_update/3` — form changesets (no persistence).
    * `create/2`, `update/3`, `delete/2` — persist through the policy and repo.

  ## See also

    * `Hawk.Writer` — the mutation pipeline primitives.
    * `Hawk.MutationContext` — carries the changeset + authority.
    * `Hawk.RepositoryBoundary` — the repo insert/update/delete wrapper.
  """

  @doc false
  defmacro __using__(opts) do
    model = Keyword.fetch!(opts, :model)
    repo = Keyword.fetch!(opts, :repo)
    policy = Keyword.fetch!(opts, :policy)
    pubsub = Keyword.get(opts, :pubsub)
    topics = Keyword.get(opts, :topics)

    quote do
      import Hawk.Writer.Resource, only: [constraint: 2, create: 1, delete: 1, update: 1]

      @hawk_writer_model unquote(model)
      @hawk_writer_repo unquote(repo)
      @hawk_writer_policy unquote(policy)
      @hawk_writer_pubsub unquote(pubsub)
      @hawk_writer_topic_strategy unquote(topics)

      @before_compile Hawk.Writer.Resource
    end
  end

  @doc """
  Declares the create pipeline. Required: a writer without a `create` block
  raises at compile time.
  """
  defmacro create(do: block) do
    quote do
      @hawk_writer_create unquote(Macro.escape(block))
    end
  end

  @doc """
  Declares the update pipeline. When omitted, `update/3` and `change_update/3`
  are not generated.
  """
  defmacro update(do: block) do
    quote do
      @hawk_writer_update unquote(Macro.escape(block))
    end
  end

  @doc """
  Enables the standard delete through the policy. Without this, `delete/2` is
  not generated.
  """
  defmacro delete(:default) do
    quote do
      @hawk_writer_delete :default
    end
  end

  @constraints ~w(unique foreign_key assoc check exclusion)a

  @doc """
  Adds a database constraint as a writer step.

  Desugars to the matching `Ecto.Changeset` constraint validator
  (`unique_constraint/3`, `foreign_key_constraint/3`, `assoc_constraint/3`,
  `check_constraint/3`, `exclusion_constraint/3`) wrapped in a
  `validate_changeset/1` call. This is the inline, one-step way to declare the
  most common DB constraints without the `validate_changeset(fn cs -> ... end)`
  indirection:

      create do
        cast([:email, :user_id])
        validate_required([:email])
        constraint(:unique, :email, name: :email_user_id_unique)
        constraint(:foreign_key, :user_id, name: :enrollments_user_id_fkey)
      end

  The desugar is pure-local: `constraint(:unique, :email, name: ...)` becomes
  `validate_changeset(fn cs -> Ecto.Changeset.unique_constraint(cs, :email, name: ...) end)`.
  """
  defmacro constraint(kind, field, opts \\ []) when kind in @constraints and is_atom(field) and is_list(opts) do
    validator = constraint_validator(kind)

    quote do
      validate_changeset(fn cs ->
        Ecto.Changeset.unquote(validator)(cs, unquote(field), unquote(opts))
      end)
    end
  end

  defp constraint_validator(:unique), do: :unique_constraint
  defp constraint_validator(:foreign_key), do: :foreign_key_constraint
  defp constraint_validator(:assoc), do: :assoc_constraint
  defp constraint_validator(:check), do: :check_constraint
  defp constraint_validator(:exclusion), do: :exclusion_constraint

  defmacro __before_compile__(env) do
    create_block = Module.get_attribute(env.module, :hawk_writer_create)
    update_block = Module.get_attribute(env.module, :hawk_writer_update)
    model = Module.get_attribute(env.module, :hawk_writer_model)
    repo = Module.get_attribute(env.module, :hawk_writer_repo)
    policy = Module.get_attribute(env.module, :hawk_writer_policy)
    delete_mode = Module.get_attribute(env.module, :hawk_writer_delete)
    pubsub = Module.get_attribute(env.module, :hawk_writer_pubsub)
    topic_strategy = Module.get_attribute(env.module, :hawk_writer_topic_strategy)
    resource = env.module |> Module.split() |> Enum.drop(-1) |> Module.concat()
    writer_opts = Macro.escape(pubsub: pubsub, resource: resource, topic_strategy: topic_strategy)

    create_context = quote_context_pipeline(:create, create_block, model, policy)
    update_functions = quote_update_functions(update_block, repo, policy)
    delete_functions = quote_delete_functions(delete_mode, repo, policy)

    quote do
      @doc false
      def __hawk_writer_opts__, do: unquote(writer_opts)

      def change_create(attrs, authority) do
        attrs
        |> create_context(authority)
        |> Hawk.Writer.changeset()
      end

      def create(attrs, authority) do
        attrs
        |> create_context(authority)
        |> Hawk.RepositoryBoundary.insert(unquote(repo), __hawk_writer_opts__())
      end

      defp create_context(attrs, authority) do
        unquote(create_context)
      end

      unquote(update_functions)
      unquote(delete_functions)
    end
  end

  defp quote_update_functions(nil, _repo, _policy), do: []

  defp quote_update_functions(update_block, repo, policy) do
    update_context = quote_context_pipeline(:update, update_block, nil, policy)

    quote do
      def change_update(model, attrs, authority) do
        model
        |> update_context(attrs, authority)
        |> Hawk.Writer.changeset()
      end

      def update(model, attrs, authority) do
        model
        |> update_context(attrs, authority)
        |> Hawk.RepositoryBoundary.update(unquote(repo), __hawk_writer_opts__())
      end

      defp update_context(model, attrs, authority) do
        unquote(update_context)
      end
    end
  end

  defp quote_delete_functions(nil, _repo, _policy), do: []

  defp quote_delete_functions(:default, repo, policy) do
    quote do
      def delete(model, authority) do
        model
        |> Hawk.MutationContext.delete(authority)
        |> Hawk.MutationContext.validate_policy(&unquote(policy).delete?/1)
        |> Hawk.RepositoryBoundary.delete(unquote(repo), __hawk_writer_opts__())
      end
    end
  end

  defp quote_context_pipeline(:create, nil, _model, _policy) do
    raise ArgumentError, "Hawk writer resource requires a create block"
  end

  defp quote_context_pipeline(:create, block, model, policy) do
    block
    |> expressions()
    |> quote_pipeline(quote(do: Hawk.MutationContext.create(%unquote(model){}, attrs, authority)))
    |> then(fn acc ->
      quote do
        unquote(acc)
        |> Hawk.MutationContext.validate_policy(&unquote(policy).create?/1)
      end
    end)
  end

  defp quote_context_pipeline(:update, block, _model, policy) do
    block
    |> expressions()
    |> quote_pipeline(quote(do: Hawk.MutationContext.update(model, attrs, authority)))
    |> then(fn acc ->
      quote do
        unquote(acc)
        |> Hawk.MutationContext.validate_policy(&unquote(policy).update?/1)
      end
    end)
  end

  defp quote_pipeline(steps, initial) do
    Enum.reduce(steps, initial, fn step, acc ->
      quote_step(step, acc)
    end)
  end

  defp quote_step({:cast, _meta, [fields]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.cast(unquote(fields))
    end
  end

  defp quote_step({:defaults, _meta, [defaults]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.defaults(unquote(defaults))
    end
  end

  defp quote_step({:validate_required, _meta, [fields]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.validate_required(unquote(fields))
    end
  end

  defp quote_step({:validate_required, _meta, [fields, opts]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.validate_required(unquote(fields), unquote(opts))
    end
  end

  defp quote_step({:validate, _meta, [validator]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.validate(unquote(validator))
    end
  end

  defp quote_step({:validate_changeset, _meta, [validator]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.validate_changeset(unquote(validator))
    end
  end

  defp quote_step({:constraint, _meta, [kind, field]}, acc) when kind in @constraints do
    quote do
      unquote(acc)
      |> Hawk.Writer.constraint(unquote(kind), unquote(field))
    end
  end

  defp quote_step({:constraint, _meta, [kind, field, opts]}, acc)
       when kind in @constraints and is_list(opts) do
    quote do
      unquote(acc)
      |> Hawk.Writer.constraint(unquote(kind), unquote(field), unquote(opts))
    end
  end

  defp quote_step(unsupported, _acc) do
    raise ArgumentError, "unsupported Hawk writer step #{Macro.to_string(unsupported)}"
  end

  defp expressions({:__block__, _meta, expressions}), do: expressions
  defp expressions(expression), do: [expression]
end
