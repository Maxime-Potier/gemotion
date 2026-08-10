class LocalizedFailureApp < Devise::FailureApp
  def i18n_message(default = nil)
    I18n.with_locale(request_locale) { super }
  end

  private

  def request_locale
    locale = request.params["locale"].presence || request.path[%r{\A/(fr|en)(?:/|\z)}, 1]
    I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
  end
end
