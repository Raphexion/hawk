defmodule Videdal.Announcements.Writer do
  @moduledoc false

  use Hawk.Writer.Resource,
    model: Videdal.Announcement,
    repo: Videdal.Repo,
    policy: Videdal.Announcements.Policy,
    pubsub: Videdal.PubSub

  create do
    cast([:body, :school_id])
    validate_required([:body])
  end

  update do
    cast([:body, :school_id])
  end

  delete(:default)
end
