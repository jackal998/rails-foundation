class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
  end

  def update
    # params.permit returns an empty hash when the form arrives without a
    # password, and update({}) succeeds against an otherwise valid record. The
    # generated controller therefore destroyed every session and announced a
    # successful reset while the old password still worked. Someone rotating a
    # password they believe is compromised would walk away with the compromised
    # one, told it was replaced.
    if params[:password].blank?
      return redirect_to edit_password_path(params[:token]), alert: "Password can't be blank."
    end

    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: "Password has been reset."
    else
      # Not a fixed "Passwords did not match": this branch is reached for every
      # validation failure, and bcrypt rejects anything over 72 bytes, which
      # forty accented characters reach. Telling someone that two identical
      # values did not match sends them round the same loop forever.
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
