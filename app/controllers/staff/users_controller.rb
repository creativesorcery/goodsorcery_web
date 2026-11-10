# Staff › Users: list and search every user, see one with all their
# accounts, and grant or remove staff access (never one's own).
class Staff::UsersController < Staff::BaseController
  before_action :set_user, only: %i[show edit update]

  def index
    @pagy, users = paginate(User.staff_search(search_query))
    @users = users.load
  end

  def show
    @memberships = @user.memberships.includes(:account).order(:id).load
  end

  def edit
  end

  def update
    if @user.update_staff(user_params[:staff], by: Current.user)
      redirect_to staff_user_path(@user), notice: staff_notice
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.expect(user: [ :staff ])
    end

    def staff_notice
      @user.staff? ? "#{@user.name} is now staff." : "#{@user.name} is no longer staff."
    end
end
