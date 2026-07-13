module ApplicationHelper
  def locale_switch_path(locale)
    route_parameters = request.path_parameters.symbolize_keys.except(:locale)
    query_parameters = request.query_parameters.symbolize_keys

    url_for(route_parameters.merge(query_parameters).merge(locale:, only_path: true))
  rescue ActionController::UrlGenerationError
    root_path(locale:)
  end

  def format_time(seconds)
    return "0:00" if seconds.nil?

    minutes, remaining_seconds = seconds.divmod(60)
    "#{minutes}:#{remaining_seconds.to_i.to_s.rjust(2, '0')}"
  end
end
