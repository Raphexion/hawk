defmodule Videdal.ScopedAnnouncements.LiveView do
  @moduledoc false

  use Hawk.LiveView.Resource

  as(:announcement)
  plural_as(:announcements)

  index do
    sort(:id)

    table do
      column(:body, label: "Body")
    end
  end

  show do
    field(:body, label: "Body")
  end
end
