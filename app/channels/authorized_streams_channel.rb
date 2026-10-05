# Turbo Stream subscriptions that need both a valid signed stream name and
# a current account membership (§4.4, §6). The signature stops tampering;
# the membership check also rejects stale names after access is revoked.
#
# Views subscribe with live_stream_from(*streamables), whose first streamable
# must be an Account, Project or Issue.
class AuthorizedStreamsChannel < ApplicationCable::Channel
  extend Turbo::Streams::Broadcasts, Turbo::Streams::StreamName
  include Turbo::Streams::StreamName::ClassMethods

  STREAMABLES = [ Account, Project, Issue ].freeze

  def subscribed
    stream_name = verified_stream_name_from_params

    if stream_name && authorized?(stream_name)
      stream_from stream_name
    else
      reject
    end
  end

  private
    def authorized?(stream_name)
      current_user.present? && streamable(stream_name)&.accessible_by?(current_user)
    end

    def streamable(stream_name)
      GlobalID::Locator.locate(stream_name.split(":").first, only: STREAMABLES)
    rescue ActiveRecord::RecordNotFound
      nil
    end
end
