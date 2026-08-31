defmodule Hawk.Reader.Page do
  @moduledoc """
  A bounded Reader page with continuation metadata.

  `entries` never contains the internal look-ahead row. `next_cursor` is an
  opaque forward cursor tied to the page's effective sort. `total_count` is
  populated when the caller requests `page[total]=true` and the page query can
  carry the unpaginated window count.
  """

  @enforce_keys [:entries, :has_more?, :page]
  defstruct [:entries, :has_more?, :next_cursor, :page, :total_count]

  @type t :: %__MODULE__{
          entries: [struct()],
          has_more?: boolean(),
          next_cursor: String.t() | nil,
          page: map(),
          total_count: non_neg_integer() | nil
        }
end
