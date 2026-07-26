Rails.application.routes.draw do
  root "posts#index"

  resources :posts, only: %i[index show new create edit update destroy] do
    resources :comments, only: %i[create update destroy]
    post "reactions", to: "reactions#toggle" # body: target, emoji
  end

  # The signed-in user's own profile (display name, bio, avatar). Singular — it's
  # always current_user's, keyed by their Cognito sub, so there's no :id.
  resource :profile, only: %i[show edit update]

  # Presigned S3 upload targets for the browser (images).
  post "/uploads", to: "uploads#create"

  # Auth. The OmniAuth request phase (POST /auth/cognito) is handled by the
  # OmniAuth middleware itself; we only route the callback, failure, and logout.
  match "/auth/cognito/callback", to: "sessions#create", via: %i[get post], as: :auth_callback
  get  "/auth/failure", to: "sessions#failure"
  delete "/logout", to: "sessions#destroy", as: :logout

  # Fake sign-in for local dev + test (no Cognito needed).
  post "/auth/dev", to: "sessions#dev_create", as: :dev_login if Rails.env.local?

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
