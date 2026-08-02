Videdal.Repo.start_link()

# A real Phoenix.PubSub for Hawk real-time tests. Hawk does not supervise a
# PubSub; the host application does. Videdal starts one here so writers that
# declare `pubsub: Videdal.PubSub` can broadcast, and so LiveView subscribe /
# refresh helpers have a running PubSub to attach to.
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: Videdal.PubSub)

ExUnit.start()
