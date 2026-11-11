require "io/console"

# bin/rails goodsorcery:create_owner: creates an account and its verified
# owner from the command line, so a fresh public instance can run with
# sign-up closed (GOODSORCERY_DISABLE_SIGNUPS=1) instead of handing the
# instance to whoever reaches the sign-up page first.
#
#   OwnerSetup.new("EMAIL" => "you@example.com", "NAME" => "You", "ACCOUNT" => "Acme").create
#   # => "Created you@example.com, owner of Acme." (or raises OwnerSetup::Failure)
#
# The password comes from PASSWORD, else from a prompt on the terminal with
# no echo. STAFF=1 also gives the owner the staff area.
class OwnerSetup
  USAGE = 'Usage: bin/rails goodsorcery:create_owner EMAIL=you@example.com NAME="Your Name" ACCOUNT="Acme" [STAFF=1]'.freeze
  NO_TERMINAL = "No terminal to prompt for the password: set PASSWORD, or run interactively (bin/kamal app exec -i ...).".freeze
  MISMATCH = "The passwords don't match.".freeze

  class Failure < StandardError; end

  def initialize(env = ENV, console: IO.console)
    @env = env
    @console = console
  end

  # The confirmation line. Raises Failure with the reason otherwise.
  def create
    signup = Signup.new(email_address: required("EMAIL"), name: required("NAME"), account_name: required("ACCOUNT"), password:)
    user = signup.save_owner(staff: staff?)
    raise Failure, "Could not create the owner: #{signup.errors.full_messages.to_sentence}." unless user

    "Created #{user.email_address}, owner of #{signup.account.name}#{" (staff)" if user.staff?}."
  end

  private
    def required(name)
      @env[name].to_s.strip.presence || raise(Failure, USAGE)
    end

    def password
      @env["PASSWORD"].presence || prompted_password
    end

    def prompted_password
      raise Failure, NO_TERMINAL unless @console

      password = @console.getpass("Password: ").to_s
      raise Failure, MISMATCH unless password == @console.getpass("Confirm password: ").to_s

      password
    end

    def staff? = @env["STAFF"] == "1"
end
