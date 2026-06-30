# Hawk

Hawk is a reusable Elixir library for building declarative reader/writer domain
contexts on top of Ecto and PostgreSQL.

Hawk depends on Ecto, Ecto SQL, and Postgrex, but it does not define or supervise
a concrete `Ecto.Repo`. Applications that use Hawk are responsible for providing
their own Repo modules, database configuration, migrations, and supervision tree.
