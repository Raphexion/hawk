defmodule Videdal.ScopedAnnouncements.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Announcement

  filter(:id)
  filter(:school_id)
  sort(:id)
  sort(:body)
end
