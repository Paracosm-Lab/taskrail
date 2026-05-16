Rails.application.routes.draw do
  devise_for :users
  resources :personal_access_tokens, only: [:index, :create, :destroy]
  get "health", to: "health#show"

  namespace :admin do
    put "log-level", to: "settings#log_level"
    put "trace-sample-rate", to: "settings#trace_sample_rate"
    get "circuit-breaker", to: "settings#circuit_breaker"
    put "circuit-breaker", to: "settings#update_circuit_breaker"
    put "maintenance", to: "settings#maintenance"
  end

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

  scope module: :web do
    root "queues#index"

    resources :queues, param: :slug, only: [:index, :show] do
      member do
        get :board
      end
    end

    resources :work_items, only: [:show, :new, :create] do
      member do
        post :retry
        post :cancel
      end
    end

    get "pipes", to: "pipes#index"
  end
end
