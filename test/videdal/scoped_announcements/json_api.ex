defmodule Videdal.ScopedAnnouncements.JsonApi do
  @moduledoc false

  use Hawk.JsonApi.Resource

  type("scoped-announcements")
  tag("Announcements", description: "Tenant-isolated real-time demo resource.")
  group("Announcements")
  doc("A broadcast announcement used to exercise the Hawk.PubSub topic-strategy escape hatch.")

  attribute(:body,
    writable: true,
    doc: "Announcement body text.",
    example: "Grades are posted."
  )
end
