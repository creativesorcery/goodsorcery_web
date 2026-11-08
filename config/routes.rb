Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :events, only: :create
      namespace :events do
        resource :batch, only: :create
      end
      get "verify", to: "verifications#show", as: :verification
      # Performance monitoring (docs/ARCHITECTURE.md §13.3).
      namespace :apm do
        resource :metrics, only: :create
        resource :traces, only: :create
      end
    end
  end

  resource :session, only: %i[new create destroy]
  resources :passwords, only: %i[new create]
  # The reset token travels as ?token= or a form field, never in the path, so
  # filter_parameters keeps it out of the "Started GET" log line.
  resource :password, only: %i[edit update]
  resource :registration, only: %i[new create]
  # Like the reset token, the verification token travels as ?token=.
  resource :email_verification, only: %i[show create]
  # One-click mute from alert emails (List-Unsubscribe), no sign-in; the
  # signed token travels as ?token= too.
  resource :alert_mute, only: %i[show create]

  resource :notifications, only: :show
  # The MCP endpoint (docs/ARCHITECTURE.md §14.2): POST only; GET and DELETE answer 405.
  resource :mcp, only: %i[show create destroy], controller: "mcp"

  resource :search, only: :show
  resource :recent_issues, only: :show

  resources :projects, only: %i[index new create edit update] do
    scope module: :projects do
      resource :setup, only: :show
      resource :card, only: :show
      resource :listening, only: :show
      resource :summary, only: :show
      resource :rows, only: :show
      resource :bulk_triage, only: :create
      resource :alerts, only: %i[show update]
      resources :alert_rules, only: :update, param: :kind
      resource :notification_preference, only: :update
      resources :api_keys, only: %i[show create] do
        scope module: :api_keys do
          resource :reveal, only: :show
          resource :rotation, only: :create
        end
      end
      # Performance (docs/ARCHITECTURE.md §13.8): overview, transaction and trace pages.
      resource :performance, only: :show, controller: "performance/overviews" do
        scope module: :performance do
          resources :transactions, only: :show
          resources :traces, only: :show
        end
      end
      resources :uptime_monitors, path: "uptime" do
        scope module: :uptime_monitors do
          resource :check, only: :create
          resource :row, only: :show
          resource :report, only: :show
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
