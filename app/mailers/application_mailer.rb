class ApplicationMailer < ActionMailer::Base
  default from: -> { self.class.sender }
  layout "mailer"
  self.deliver_later_queue_name = :mailers
  helper :mailer

  # GOODSORCERY_MAIL_FROM, else no-reply at the host emails link to.
  def self.sender
    ENV.fetch("GOODSORCERY_MAIL_FROM") { "Good Sorcery <no-reply@#{default_url_options.fetch(:host, 'localhost')}>" }
  end
end
