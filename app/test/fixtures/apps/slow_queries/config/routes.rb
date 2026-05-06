Rails.application.routes.draw do
  resources :posts, only: [:index] do
    collection do
      get :published
    end
  end
end
