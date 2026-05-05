Rails.application.routes.draw do
  resources :orders, only: [:show, :update]
  namespace :admin do
    resources :reports, only: [:index]
  end
  post "/webhooks/legacy", to: "webhooks#create"
end
