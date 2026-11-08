# Live updates subscribe only through AuthorizedStreamsChannel, which also
# re-checks account membership. The stock Turbo::StreamsChannel accepts the
# same never-expiring signed stream names with no membership check, and Action
# Cable lets a client name any channel class, so a removed member could keep
# listening through it. It refuses every subscription; broadcasting through its
# class methods (LiveFrames, UptimeMonitor::Broadcasting) is unaffected.
Rails.application.config.to_prepare do
  Turbo::StreamsChannel.class_eval do
    def subscribed = reject
  end
end
