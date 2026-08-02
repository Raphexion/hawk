defmodule Videdal.Announcements.JsonApi do
  @moduledoc false

  use Hawk.JsonApi.Resource

  type("announcements")
  tag("Announcements", description: "Real-time broadcast demo resource.")
  group("Announcements")
  doc("A broadcast announcement used to exercise Hawk.PubSub.")

  attribute(:body,
    writable: true,
    doc: "Announcement body text.",
    example: "Grades are posted."
  )
end
