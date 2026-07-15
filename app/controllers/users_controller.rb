class UsersController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(user_params_withput_password)
      redirect_to user_path(@user), notice: t("profile.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :phone, :password, :password_confirmation)
  end

  def user_params_withput_password
    params.require(:user).permit(:first_name, :last_name, :email, :phone)
  end
end
