defmodule Videdal.Announcements.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Announcement

  filter(:id)
  sort(:id)
  sort(:body)
end
