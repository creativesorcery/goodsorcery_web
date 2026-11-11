module ApplicationCable
  # Identified by user and browser session, so ending one session
  # (Session#terminate) closes only that browser's connection.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session

    def connect
      set_current_session || reject_unauthorized_connection
    end

    private
      def set_current_session
        if session = Session.active.includes(:user).find_by(id: cookies.signed[:session_id])
          self.current_session = session
          self.current_user = session.user
        end
      end
  end
end
