defmodule Hawk.Reader.Resource do
  @moduledoc """
  Declarative reader DSL for Hawk resources.

  The DSL stores resource-owned reader declarations and generates the standard
  public reader API by delegating execution to `Hawk.Reader`.
  """

  @required_options [:repo, :schema, :policy]

  defmacro __using__(opts) do
    validate_options!(opts)

    repo = Keyword.fetch!(opts, :repo)
    schema = Keyword.fetch!(opts, :schema)
    policy = Keyword.fetch!(opts, :policy)
    forced_filter = Keyword.get(opts, :forced_filter, :all)

    quote do
      import Ecto.Query
      import Hawk.Reader.Resource, only: [filter: 1, filter: 2]

      @hawk_reader_repo unquote(repo)
      @hawk_reader_schema unquote(schema)
      @hawk_reader_policy unquote(policy)
      @hawk_reader_forced_filter unquote(Macro.escape(forced_filter))

      Module.register_attribute(__MODULE__, :hawk_reader_filter_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_filter_handlers, accumulate: true)

      @before_compile Hawk.Reader.Resource
    end
  end

  defmacro filter(key) when is_atom(key) do
    quote do
      @hawk_reader_filter_keys unquote(key)
    end
  end

  defmacro filter(key, do: block) when is_atom(key) do
    handler_name = :"__hawk_filter_#{key}__"

    quote do
      @hawk_reader_filter_keys unquote(key)
      @hawk_reader_filter_handlers {unquote(key), unquote(handler_name)}

      defp unquote(handler_name)(value) do
        handler = unquote(block)
        handler.(value)
      end
    end
  end

  defmacro __before_compile__(env) do
    filter_keys =
      env.module
      |> Module.get_attribute(:hawk_reader_filter_keys)
      |> Enum.reverse()

    filter_handlers =
      env.module
      |> Module.get_attribute(:hawk_reader_filter_handlers)
      |> Enum.reverse()

    handler_entries =
      Enum.map(filter_handlers, fn {key, handler_name} ->
        quote do
          {unquote(key), fn value -> unquote(handler_name)(value) end}
        end
      end)

    quote do
      def filter_keys do
        MapSet.new(unquote(filter_keys))
      end

      def filter_handlers do
        Map.new([unquote_splicing(handler_entries)])
      end

      def read_filter(authority) do
        @hawk_reader_policy.read_filter(authority)
      end

      def one(opts), do: Hawk.Reader.one(config(), opts)
      def one!(opts), do: Hawk.Reader.one!(config(), opts)
      def all(opts), do: Hawk.Reader.all(config(), opts)

      defp config do
        %{
          repo: @hawk_reader_repo,
          schema: @hawk_reader_schema,
          filter_keys: filter_keys(),
          filter_handlers: filter_handlers(),
          read_filter: &read_filter/1,
          forced_filter: @hawk_reader_forced_filter
        }
      end
    end
  end

  defp validate_options!(opts) do
    Enum.each(@required_options, fn option ->
      unless Keyword.has_key?(opts, option) do
        raise ArgumentError, "missing required reader option #{inspect(option)}"
      end
    end)
  end
end
