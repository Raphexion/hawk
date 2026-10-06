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
    * `authorize_relationships([:association, ...])` — authorize references through their readers.
      Entries may also be `{association, ReaderModule}` to override discovery.
      The check runs after preparation and write-policy validation, regardless
      of its position in the block. Multiple declarations share one SQL query.
      Optional nil identifiers are skipped; use `validate_required` for required
      relationships. Updates check all effective identifiers, including unchanged
      ones. Inaccessible references return `:not_authorized` and invalidate form
      changesets. Related readers must use the writer's repo.
      This grants permission to reference a visible record, not to modify it.
      Foreign-key constraints remain necessary, and eligibility depending on a
      pair of records still needs an application policy or database constraint.
    * `constraint(kind, field, opts)` — declare a DB constraint (see `constraint/3`).

  `delete(:default)` enables the standard hard delete through the policy.
  `soft_delete(:field)` instead generates reversible `delete/2`, `restore/2`,
  and explicit `hard_delete/2` operations.

  Use a `delete do ... end` block containing `authorize_relationships/1`
  declarations to check the model's existing references before deletion. The
  block enables ordinary hard deletion, or combines with `soft_delete(:field)`
  in either declaration order. Its checks apply to both `delete/2` and explicit
  `hard_delete/2`, after their respective write policies. Multiple declarations
  share one SQL query. `restore/2` continues to use its own policy.
  Other writer steps are not supported in delete blocks.

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
      A soft-delete writer also generates `restore/2` and `hard_delete/2`.

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
      import Hawk.Writer.Resource, only: [constraint: 2, create: 1, delete: 1, soft_delete: 1, update: 1]

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
  Enables deletion through the policy. `delete(:default)` generates ordinary
  hard deletion. A `delete do` block declares relationship authorization and
  enables ordinary hard deletion when no `soft_delete/1` is configured.

  With `soft_delete/1`, the block's declarations apply to both `delete/2` and
  `hard_delete/2`; `restore/2` retains its own policy. Only
  `authorize_relationships/1` steps are supported in delete blocks.
  """
  defmacro delete(:default) do
    quote do
      @hawk_writer_delete :default
    end
  end

  defmacro delete(do: block) do
    quote do
      @hawk_writer_delete_block unquote(Macro.escape(block))
    end
  end

  @doc """
  Makes ordinary deletion reversible through a nullable timestamp field and
  generates explicit `restore/2` and `hard_delete/2` operations.
  """
  defmacro soft_delete(field) when is_atom(field) do
    quote do
      @hawk_writer_delete {:soft, unquote(field)}
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
    delete_block = Module.get_attribute(env.module, :hawk_writer_delete_block)
    delete_mode = Module.get_attribute(env.module, :hawk_writer_delete) || if(delete_block, do: :default)
    validate_delete_block!(delete_block)
    pubsub = Module.get_attribute(env.module, :hawk_writer_pubsub)
    topic_strategy = Module.get_attribute(env.module, :hawk_writer_topic_strategy)
    resource = env.module |> Module.split() |> Enum.drop(-1) |> Module.concat()
    writer_opts = Macro.escape(pubsub: pubsub, resource: resource, topic_strategy: topic_strategy)

    create_context = quote_context_pipeline(:create, create_block, model, policy)
    update_functions = quote_update_functions(update_block, repo, policy)
    delete_functions = quote_delete_functions(delete_mode, delete_block, repo, policy)

    validate_soft_delete!(model, delete_mode)

    quote do
      @doc false
      def __hawk_writer_opts__, do: unquote(writer_opts)

      @doc false
      def __hawk_soft_delete__, do: unquote(delete_mode)

      @spec change_create(map(), Hawk.Authority.t()) :: Ecto.Changeset.t()
      def change_create(attrs, authority) do
        attrs
        |> create_context(authority)
        |> Hawk.Writer.changeset()
      end

      @spec create(map(), Hawk.Authority.t()) :: Hawk.Result.t(struct())
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
      @spec change_update(struct(), map(), Hawk.Authority.t()) :: Ecto.Changeset.t()
      def change_update(model, attrs, authority) do
        model
        |> update_context(attrs, authority)
        |> Hawk.Writer.changeset()
      end

      @spec update(struct(), map(), Hawk.Authority.t()) :: Hawk.Result.t(struct())
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

  defp quote_delete_functions(nil, _block, _repo, _policy), do: []

  defp quote_delete_functions(:default, block, repo, policy) do
    initial = quote(do: Hawk.MutationContext.delete(model, authority))
    context = quote_delete_context(block, initial, policy, :delete?)

    quote do
      @spec delete(struct(), Hawk.Authority.t()) :: Hawk.Result.t(struct())
      def delete(model, authority) do
        unquote(context)
        |> Hawk.RepositoryBoundary.delete(unquote(repo), __hawk_writer_opts__())
      end
    end
  end

  defp quote_delete_functions({:soft, field}, block, repo, policy) do
    initial =
      quote do
        model
        |> Hawk.MutationContext.delete(authority, %{unquote(field) => DateTime.utc_now(:second)})
        |> Hawk.Writer.cast([unquote(field)])
      end

    delete_context = quote_delete_context(block, initial, policy, :delete?)
    hard_delete_initial = quote(do: Hawk.MutationContext.hard_delete(model, authority))
    hard_delete_context = quote_delete_context(block, hard_delete_initial, policy, :hard_delete?)

    quote do
      @spec delete(struct(), Hawk.Authority.t()) :: Hawk.Result.t(struct())
      def delete(model, authority) do
        unquote(delete_context)
        |> Hawk.RepositoryBoundary.update(unquote(repo), __hawk_writer_opts__())
      end

      @spec restore(struct(), Hawk.Authority.t()) :: Hawk.Result.t(struct())
      def restore(model, authority) do
        model
        |> Hawk.MutationContext.restore(authority, %{unquote(field) => nil})
        |> Hawk.Writer.cast([unquote(field)])
        |> Hawk.MutationContext.validate_policy(&unquote(policy).restore?/1)
        |> Hawk.RepositoryBoundary.update(unquote(repo), __hawk_writer_opts__())
      end

      @spec hard_delete(struct(), Hawk.Authority.t()) :: Hawk.Result.t(struct())
      def hard_delete(model, authority) do
        unquote(hard_delete_context)
        |> Hawk.RepositoryBoundary.delete(unquote(repo), __hawk_writer_opts__())
      end
    end
  end

  defp quote_delete_context(nil, initial, policy, predicate) do
    quote do
      unquote(initial)
      |> Hawk.MutationContext.validate_policy(&(unquote(policy).unquote(predicate) / 1))
    end
  end

  defp quote_delete_context(block, initial, policy, predicate) do
    quote_authorized_pipeline(block, initial, policy, predicate)
  end

  defp validate_delete_block!(nil), do: :ok

  defp validate_delete_block!(block) do
    Enum.each(expressions(block), fn
      {:authorize_relationships, _, [_relationships]} -> :ok
      step -> raise ArgumentError, "unsupported Hawk delete step #{Macro.to_string(step)}"
    end)
  end

  defp validate_soft_delete!(_model, mode) when mode in [nil, :default], do: :ok

  defp validate_soft_delete!(model, {:soft, field}) do
    unless field in model.__schema__(:fields) do
      raise ArgumentError,
            "soft_delete field #{inspect(field)} is not a field on #{inspect(model)}"
    end
  end

  defp quote_context_pipeline(:create, nil, _model, _policy) do
    raise ArgumentError, "Hawk writer resource requires a create block"
  end

  defp quote_context_pipeline(:create, block, model, policy) do
    initial = quote(do: Hawk.MutationContext.create(%unquote(model){}, attrs, authority))
    quote_authorized_pipeline(block, initial, policy, :create?)
  end

  defp quote_context_pipeline(:update, block, _model, policy) do
    initial = quote(do: Hawk.MutationContext.update(model, attrs, authority))
    quote_authorized_pipeline(block, initial, policy, :update?)
  end

  defp quote_authorized_pipeline(block, initial, policy, predicate) do
    {authorization, preparation} =
      block |> expressions() |> Enum.split_with(&match?({:authorize_relationships, _, _}, &1))

    prepared = quote_pipeline(preparation, initial)

    checked =
      quote do
        unquote(prepared)
        |> Hawk.MutationContext.validate_policy(&(unquote(policy).unquote(predicate) / 1))
      end

    # Reference declarations cannot grant write access. Gate the writer first,
    # and combine all reference declarations into a single authorization query.
    case authorization do
      [] ->
        checked

      steps ->
        relationships =
          Enum.map(steps, fn
            {:authorize_relationships, _, [relationships]} -> relationships
            step -> raise ArgumentError, "unsupported Hawk writer step #{Macro.to_string(step)}"
          end)

        quote do
          unquote(checked)
          |> Hawk.Writer.authorize_relationships(List.flatten(unquote(relationships)), @hawk_writer_repo)
        end
    end
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
