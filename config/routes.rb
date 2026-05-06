Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get "queues", to: "queues#index"
      get "queues/:slug/stages", to: "queues#stages"

      resources :work_items, only: [:index, :show, :create] do
        member do
          post :answer
          post :retry
          post :cancel
        end
      end

      get "pipes", to: "pipes#index"
      get "pipes/:slug", to: "pipes#show"

      get "costs", to: "costs#index"
      get "costs/work_items/:id", to: "costs#work_item"
      get "digest", to: "digests#show"
      get "stream", to: "streams#show"
      post "webhooks/github/pull_request", to: "github_pr_webhooks#create"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
