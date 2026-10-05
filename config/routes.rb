Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :events, only: :create
    end
  end

  resource :session, only: %i[new create destroy]
  resources :passwords, only: %i[new create]
  # The reset token travels as ?token= or a form field, never in the path, so
  # filter_parameters keeps it out of the "Started GET" log line.
  resource :password, only: %i[edit update]
  resource :registration, only: %i[new create]

  resource :search, only: :show
  resource :recent_issues, only: :show

  resources :projects, only: %i[index new create edit update] do
    scope module: :projects do
      resource :setup, only: :show
      resource :card, only: :show
      resource :listening, only: :show
      resource :summary, only: :show
      resource :bulk_triage, only: :create
      resources :api_keys, only: %i[show create] do
        scope module: :api_keys do
          resource :reveal, only: :show
          resource :rotation, only: :create
        end
      end
    end

    resources :issues, only: %i[index show] do
      scope module: :issues do
        resource :row, only: :show
        resource :stats, only: :show
        resource :chart, only: :show
        resource :resolution, only: %i[create destroy]
        resource :ignore, only: %i[create destroy]
        resource :assignment, only: %i[update destroy]
        resources :occurrences, only: :show
        resources :notes, only: :create
      end
    end
  end

  root "projects#index"
end
