require "test_helper"

class AccessTokensControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:philip) }

  def create_token(name: "Claude Code", scopes: %w[triage], expires_in: "90", format: :turbo_stream, **extra)
    post access_tokens_path, params: { personal_access_token: { name:, scopes:, expires_in:, **extra } },
      headers: format == :turbo_stream ? { "Accept" => "text/vnd.turbo-stream.html" } : {}
  end

  def created_token_text = css_select("#created_access_token_value").first.text

  test "requires sign in" do
    sign_out
    get access_tokens_path
    assert_redirected_to new_session_path

    post access_tokens_path, params: { personal_access_token: { name: "x" } }
    assert_redirected_to new_session_path
  end

  test "lists the person's own tokens with status, scopes, use and recent MCP activity" do
    get access_tokens_path

    assert_response :success
    assert_select "h1", "MCP server"
    assert_select "title", /MCP server/
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "##{dom_id(personal_access_tokens(:philip_triage))}" do
      assert_select "span", text: "Claude Code"
      assert_select ".chip", text: "Triage"
      assert_select "button", text: "Revoke"
      assert_select "details summary", text: "Recent activity (1)"
      assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:resolved_issue)), text: "GS-1020"
    end
    assert_select "##{dom_id(personal_access_tokens(:philip_revoked))}" do
      assert_select ".chip", text: "Revoked"
      assert_select "button", text: "Revoke", count: 0
    end
    assert_select "##{dom_id(personal_access_tokens(:philip_expired))} .chip", text: "Expired"
    assert_select "##{dom_id(personal_access_tokens(:jo_read))}", 0
    assert_select "##{dom_id(personal_access_tokens(:outsider_read))}", 0
    PAT_FIXTURE_TOKENS.each_value { |token| assert_not_includes response.body, token }
    assert_no_match(/style="/, response.body)
  end

  test "the user menu links here as MCP server" do
    get projects_path
    assert_select "a.menu-item[href=?]", access_tokens_path, text: /MCP server/
  end

  test "shows how to connect a client before any token exists, with a placeholder instead of a token" do
    sign_in_as users(:jo)
    users(:jo).personal_access_tokens.destroy_all
    get access_tokens_path

    assert_select "#connect_client" do
      assert_select "h2", "Connect a client"
      assert_select "ol li", 2
      assert_select "a[href='#new_access_token']", text: "Create an access token"
      assert_select "#mcp_server_url[data-clipboard-target=source]", "http://www.example.com/mcp"
      assert_select "#mcp_server_url ~ button[aria-label]", 0
      assert_select "#mcp_server_url ~ button [data-clipboard-target=label]", "Copy"
      assert_select "#mcp_server_url ~ button .sr-only", "server URL"
      assert_select "[role=tab]", AccessTokensHelper::CLIENTS.size
      assert_select ".tab-strip[role=tablist]", 1, "the client tabs scroll sideways on phones instead of wrapping"
      assert_select "a[href=?][target=_blank][rel='noopener noreferrer']", AccessTokensHelper::MCP_GUIDE_URL
    end
    assert_select "#created_access_token", 0
    assert_includes response.body, "claude mcp add --transport http goodsorcery http://www.example.com/mcp --header &quot;Authorization: Bearer &lt;your-token&gt;&quot;"
    assert_includes response.body, "export GOODSORCERY_TOKEN=&quot;&lt;your-token&gt;&quot;"
    assert_includes response.body, "&quot;Authorization&quot;: &quot;Bearer &lt;your-token&gt;&quot;"
    assert_includes response.body, "Bearer ${input:goodsorcery-token}"
    assert_match "claude.ai and Claude Desktop aren", response.body
    assert_select "p.hint", text: /GOODSORCERY_TOKEN environment variable/
    assert_select "p.hint", text: /VS Code asks for the token/
    assert_select "#new_access_token"
    assert_no_match(/gs_pat_[A-Za-z0-9]/, response.body)
  end

  test "the connect panel stays on a failed create" do
    create_token(name: "", format: :html)
    assert_select "#connect_client"
    assert_select "#created_access_token", 0
  end

  test "the form explains the scopes and warns about request data" do
    get access_tokens_path

    assert_select "#new_access_token" do
      assert_select "input[type=checkbox][disabled][checked]"
      assert_select "input[name='personal_access_token[scopes][]'][value=triage]"
      assert_select "input[name='personal_access_token[scopes][]'][value=request_data]"
      assert_select "select[name='personal_access_token[expires_in]'] option[selected]", text: "90 days"
      assert_select "select[name='personal_access_token[account_id]']", 0, "one account: no account select"
    end
    assert_match "sends request params, headers and user details", response.body
  end

  test "creates a token and shows it once with client snippets" do
    assert_difference -> { users(:philip).personal_access_tokens.count } do
      create_token
    end

    assert_response :success
    token = users(:philip).personal_access_tokens.recent_first.first
    plaintext = created_token_text
    assert_equal token, PersonalAccessToken.authenticate(plaintext)
    assert_equal %w[read triage], token.scopes
    assert_equal accounts(:acme), token.account
    assert_in_delta 90.days.from_now, token.expires_at, 1.minute

    assert_includes response.body, "claude mcp add --transport http goodsorcery http://www.example.com/mcp --header &quot;Authorization: Bearer #{plaintext}&quot;"
    assert_includes response.body, "bearer_token_env_var = &quot;GOODSORCERY_TOKEN&quot;"
    assert_includes response.body, "export GOODSORCERY_TOKEN=&quot;#{plaintext}&quot;"
    assert_includes response.body, "~/.cursor/mcp.json"
    assert_includes response.body, "promptString"
    assert_match "claude.ai and Claude Desktop aren", response.body
    assert_select "#created_access_token #mcp_server_url", "http://www.example.com/mcp"
    assert_select "[role=tablist][aria-label='AI client']", 1, "the new token's snippets replace the placeholder ones"
    assert_select "#connect_client", 0
    assert_not_includes response.body, AccessTokensHelper::TOKEN_PLACEHOLDER.gsub("<", "&lt;").gsub(">", "&gt;")

    get access_tokens_path
    assert_not_includes response.body, plaintext, "shown only in the create response"
    assert_includes response.body, token.masked_token
  end

  test "the plain HTML create renders the page with the token too" do
    create_token(format: :html)
    assert_response :created
    assert PersonalAccessToken.authenticate(created_token_text)
  end

  test "snippets use GOODSORCERY_PUBLIC_URL when set" do
    previous = Rails.configuration.x.public_url
    Rails.configuration.x.public_url = PublicUrl.new("https://app.goodsorcery.com")
    create_token
    assert_includes response.body, "https://app.goodsorcery.com/mcp"
  ensure
    Rails.configuration.x.public_url = previous
  end

  test "never puts the token in the flash, session, cache or logs" do
    log = StringIO.new
    previous = Rails.logger
    Rails.logger = ActionController::Base.logger = ActiveSupport::Logger.new(log)
    with_memory_cache do
      create_token
      plaintext = created_token_text

      assert_nil flash[:notice]
      assert_not_includes session.to_hash.to_json, plaintext
      assert_not_includes log.string, plaintext
      assert_not_includes Rails.cache.instance_variable_get(:@data).to_s, plaintext
    end
  ensure
    Rails.logger = ActionController::Base.logger = previous
  end

  test "drops unknown scopes and defaults expiry" do
    create_token(scopes: %w[admin request_data], expires_in: "bogus")

    token = users(:philip).personal_access_tokens.recent_first.first
    assert_equal %w[read request_data], token.scopes
    assert_in_delta 90.days.from_now, token.expires_at, 1.minute
  end

  test "never expiring tokens" do
    create_token(expires_in: "never")
    assert_nil users(:philip).personal_access_tokens.recent_first.first.expires_at
  end

  test "422 with the error for an invalid token" do
    assert_no_difference -> { PersonalAccessToken.count } do
      create_token(name: "", format: :html)
    end
    assert_response :unprocessable_entity
    assert_select "#new_access_token [role=alert]", text: /Name can't be blank/
  end

  test "creating a token for another account is a 404" do
    assert_no_difference -> { PersonalAccessToken.count } do
      create_token(account_id: accounts(:umbrella).id)
    end
    assert_response :not_found
  end

  test "lets members of several accounts choose the account" do
    accounts(:umbrella).memberships.create!(user: users(:philip))

    get access_tokens_path
    assert_select "select[name='personal_access_token[account_id]'] option", 2

    create_token(account_id: accounts(:umbrella).id)
    assert_equal accounts(:umbrella), users(:philip).personal_access_tokens.recent_first.first.account
  end

  test "creating a token needs a confirmed email address" do
    users(:philip).update!(email_verified_at: nil)

    assert_no_difference -> { PersonalAccessToken.count } do
      create_token(format: :html)
    end
    assert_redirected_to root_path
  end

  test "revokes the person's own token" do
    delete access_token_path(personal_access_tokens(:philip_read))

    assert_redirected_to access_tokens_path
    assert personal_access_tokens(:philip_read).reload.revoked?
    assert_nil PersonalAccessToken.authenticate(PAT_FIXTURE_TOKENS[:philip_read])
  end

  test "another person's token is a 404, in the same account or another" do
    [ :jo_read, :outsider_read ].each do |name|
      delete access_token_path(personal_access_tokens(name))
      assert_response :not_found
      assert_not personal_access_tokens(name).reload.revoked?
    end
  end

  test "an outsider sees none of this account's tokens" do
    sign_in_as users(:outsider)
    get access_tokens_path

    assert_select "##{dom_id(personal_access_tokens(:outsider_read))}"
    assert_select "##{dom_id(personal_access_tokens(:philip_read))}", 0
    assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:resolved_issue)), 0
  end

  test "every active token stays listed and revocable however many ended tokens are newer" do
    old = personal_access_tokens(:philip_full)
    old.update_columns(created_at: 1.year.ago, expires_at: nil)
    travel 1.minute do
      55.times { |n| users(:philip).personal_access_tokens.create!(account: accounts(:acme), name: "Throwaway #{n}").revoke }
    end

    get access_tokens_path

    assert_select "##{dom_id(old)}" do
      assert_select "form[action=?]", access_token_path(old)
    end
    assert_select "li[id^='personal_access_token_']", PersonalAccessToken.active.where(user: users(:philip)).count + AccessTokensController::ENDED_LIMIT
  end

  test "renders in a fixed number of queries however many tokens and activities there are" do
    get access_tokens_path
    baseline = count_queries { get access_tokens_path }

    3.times do |n|
      token = users(:philip).personal_access_tokens.create!(account: accounts(:acme), name: "Extra #{n}")
      AccessTokenActivity.record(token, "ignore", [ issues(:card_error).id ])
    end

    assert_equal baseline, count_queries { get access_tokens_path }
  end

  private
    def count_queries(&)
      queries = []
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
      queries.size
    end
end
