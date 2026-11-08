# The signed-in person's personal access tokens for AI clients (user menu ›
# Access tokens, docs/MCP.md): list with recent MCP activity, create, revoke.
# Tokens belong to the person, each covering one of their accounts. The
# plaintext token appears only in the create response; it never goes into
# the flash, the session, the cache or a log (the request log shows only
# the form's name, account, scopes and expiry).
class AccessTokensController < ApplicationController
  include VerifiedEmailRequired

  require_verified_email only: :create

  # Every active token is listed (at most PersonalAccessToken::MAX_ACTIVE_PER_USER),
  # then up to this many revoked or expired ones, newest first.
  ENDED_LIMIT = 30

  def index
    @access_token = PersonalAccessToken.new(account: Current.account)
  end

  def create
    @access_token = Current.user.personal_access_tokens.new(access_token_params)
    return render(:index, status: :unprocessable_entity) unless @access_token.save

    @created_token = @access_token
    @access_token = PersonalAccessToken.new(account: @created_token.account)
    respond_to_created
  end

  def destroy
    token = Current.user.personal_access_tokens.find(params[:id])
    token.revoke
    redirect_to access_tokens_path, status: :see_other,
      notice: "#{token.name} is revoked. Clients using it lose access at once."
  end

  private
    def access_token_params
      permitted = params.expect(personal_access_token: [ :name, :account_id, :expires_in, scopes: [] ])
      { name: permitted[:name], account: token_account(permitted[:account_id]),
        scopes: Array(permitted[:scopes]) & PersonalAccessToken::OPTIONAL_SCOPES,
        expires_at: PersonalAccessToken.expiry_for(permitted[:expires_in]) }
    end

    # One of the person's own accounts (another account's id is a 404), else the current one.
    def token_account(id)
      id.present? ? Current.user.accounts.find(id) : Current.account
    end

    def respond_to_created
      respond_to do |format|
        format.turbo_stream
        format.html { render :index, status: :created }
      end
    end

    # Active tokens first, all of them, so none can be pushed off the page.
    helper_method def access_tokens
      @access_tokens ||= own_tokens.active.to_a + own_tokens.ended.limit(ENDED_LIMIT).to_a
    end

    def own_tokens = Current.user.personal_access_tokens.where(account: Current.user.accounts).includes(:account).recent_first

    helper_method def token_activities
      @token_activities ||= AccessTokenActivity.recent_by_token(access_tokens.map(&:id))
    end

    # { issue id => issue } for the activity rows, limited to the person's accounts (two queries).
    helper_method def activity_issues
      @activity_issues ||= Issue.where(id: token_activities.values.flatten.flat_map(&:issue_ids).uniq)
        .where(project_id: Project.where(account: Current.user.accounts).select(:id)).includes(:project).index_by(&:id)
    end
end
