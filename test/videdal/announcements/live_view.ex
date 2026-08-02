defmodule Videdal.Announcements.LiveView do
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

  create_form do
    field(:body, label: "Body")
  end

  update_form do
    field(:body, label: "Body")
  end
end
