Rails.application.routes.draw do
  get "/reports", to: "reports#index"
  get "/reports/export", to: "reports#export"
end
