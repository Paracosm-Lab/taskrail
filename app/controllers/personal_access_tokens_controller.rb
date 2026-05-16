class PersonalAccessTokensController < Web::BaseController
  def index
    @personal_access_tokens = current_user.personal_access_tokens.order(created_at: :desc)
  end

  def create
    scopes = permitted_scopes
    token, raw_token = PersonalAccessToken.generate!(
      user: current_user,
      name: params.require(:personal_access_token).require(:name),
      scopes: scopes,
      expires_at: expires_at
    )
    flash[:created_token] = raw_token
    redirect_to personal_access_tokens_path, notice: "Personal access token created"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to personal_access_tokens_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    current_user.personal_access_tokens.find(params[:id]).revoke!
    redirect_to personal_access_tokens_path, notice: "Personal access token revoked"
  end

  private

  def permitted_scopes
    requested = Array(params.require(:personal_access_token)[:scopes]).reject(&:blank?)
    requested &= PersonalAccessToken::SCOPES
    requested -= ["admin"] unless current_user.admin?
    requested.presence || ["read"]
  end

  def expires_at
    raw_value = params.require(:personal_access_token)[:expires_at].presence
    return nil unless raw_value

    Time.zone.parse(raw_value)
  end
end
