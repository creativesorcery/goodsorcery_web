# Staff › Accounts: list and search every account, see one with its members
# and entitlements, and edit those entitlements (Staff::EntitlementsForm).
class Staff::AccountsController < Staff::BaseController
  before_action :set_account, only: %i[show edit update]

  def index
    @pagy, accounts = paginate(Account.staff_search(search_query))
    @accounts = accounts.with_users_count.load
  end

  def show
    @form = Staff::EntitlementsForm.new(@account)
    @memberships = @account.memberships.includes(:user).order(:id).load
  end

  def edit
    @form = Staff::EntitlementsForm.new(@account)
  end

  def update
    @form = Staff::EntitlementsForm.new(@account, entitlements_params)
    if @form.save
      redirect_to staff_account_path(@account), notice: "Saved #{@account.name}'s entitlements."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_account
      @account = Account.find(params[:id])
    end

    def entitlements_params
      params.expect(entitlements: Staff::EntitlementsForm::PERMITTED)
    end
end
