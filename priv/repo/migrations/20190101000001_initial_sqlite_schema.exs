defmodule Plausible.Repo.Migrations.InitialSqliteSchema do
  @moduledoc """
  Consolidated SQLite-compatible migration that creates all tables with their
  final schema definitions, replacing all individual PostgreSQL migrations.

  This migration runs before the Oban and fun_with_flags migrations.
  """

  use Ecto.Migration

  def change do
    # ============================================================================
    # USERS
    # ============================================================================
    create table(:users) do
      add :email, :string, null: false
      add :password_hash, :string
      add :name, :string
      add :last_seen, :naive_datetime
      add :theme, :string, default: "system"
      add :email_verified, :boolean, default: false
      add :previous_email, :string
      add :notes, :string

      # TOTP fields
      add :totp_enabled, :boolean, default: false
      add :totp_secret, :binary
      add :totp_secret_fallback, :binary
      add :totp_token, :string
      add :totp_last_used_at, :naive_datetime

      # Context perseverance across sessions
      add :last_team_identifier, :binary

      # SSO fields (EE)
      add :type, :string, default: "standard"
      add :sso_identity_id, :string
      add :last_sso_login, :naive_datetime
      add :sso_integration_id, references(:sso_integrations, on_delete: :nilify_all)
      add :sso_domain_id, references(:sso_domains, on_delete: :nilify_all)

      # CE-only field for backfill teams migration
      add :trial_expiry_date, :date

      timestamps()
    end

    create unique_index(:users, [:email])
    create index(:users, [:sso_integration_id])
    create index(:users, [:sso_domain_id])
    create_if_not_exists unique_index(:users, [:sso_identity_id])

    # ============================================================================
    # SSO INTEGRATIONS (EE)
    # ============================================================================
    create table(:sso_integrations) do
      add :identifier, :binary, null: false
      add :config, :map, null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:sso_integrations, [:team_id])
    create unique_index(:sso_integrations, [:identifier])

    # ============================================================================
    # SSO DOMAINS (EE)
    # ============================================================================
    create table(:sso_domains) do
      add :identifier, :binary, null: false
      add :domain, :string, null: false
      add :verified_via, :string
      add :last_verified_at, :naive_datetime
      add :status, :string, null: false
      add :sso_integration_id, references(:sso_integrations, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:sso_domains, [:identifier])
    create unique_index(:sso_domains, [:domain])
    create index(:sso_domains, [:sso_integration_id])

    # ============================================================================
    # TEAMS
    # ============================================================================
    create table(:teams) do
      add :identifier, :binary_id, null: false
      add :name, :string, null: false
      add :trial_expiry_date, :date
      add :accept_traffic_until, :date
      add :allow_next_upgrade_override, :boolean, default: false
      add :grace_period, :map
      add :locked, :boolean, default: false
      add :locked_by_admin, :boolean, default: false
      add :setup_complete, :boolean, default: false
      add :setup_at, :naive_datetime
      add :hourly_api_request_limit, :integer, default: 600
      add :notes, :string
      add :policy, :map, null: false, default: "{}"

      timestamps()
    end

    create unique_index(:teams, [:identifier])

    # ============================================================================
    # SITES
    # ============================================================================
    create table(:sites) do
      add :domain, :string, null: false
      add :timezone, :string, default: "Etc/UTC"
      add :public, :boolean, default: false
      add :stats_start_date, :date
      add :native_stats_start_at, :naive_datetime
      add :onboarding_status, :string, default: "completed"
      add :allowed_event_props, :string
      add :conversions_enabled, :boolean, default: true
      add :props_enabled, :boolean, default: true
      add :funnels_enabled, :boolean, default: true
      add :legacy_time_on_page_cutoff, :date, default: "1970-01-01"
      add :consolidated, :boolean, default: false
      add :ingest_rate_limit_scale_seconds, :integer, default: 60
      add :ingest_rate_limit_threshold, :integer
      add :domain_changed_from, :string
      add :domain_changed_at, :naive_datetime
      add :imported_data, :map
      add :installation_meta, :map
      add :team_id, references(:teams, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:sites, [:domain])
    create index(:sites, [:team_id])
    create index(:sites, [:updated_at])
    create unique_index(:sites, [:domain_changed_from])
    create index(:sites, [:domain_changed_at])
    create index(:sites, [:team_id, :consolidated, :id])

    # ============================================================================
    # API KEYS
    # ============================================================================
    create table(:api_keys) do
      add :name, :string, null: false
      add :scopes, :string, default: "[\"stats:read:*\"]"
      add :key_hash, :string
      add :key_prefix, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :team_id, references(:teams, on_delete: :delete_all)

      timestamps()
    end

    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:user_id])
    create index(:api_keys, [:team_id])

    # ============================================================================
    # GOALS
    # ============================================================================
    create table(:goals) do
      add :event_name, :string
      add :page_path, :string
      add :scroll_threshold, :integer, default: -1
      add :display_name, :string
      add :currency, :string
      add :custom_props, :string, default: "{}"
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:goals, [:site_id, :event_name, :custom_props],
             name: :goals_event_config_unique
           )
    create unique_index(:goals, [:site_id, :page_path, :scroll_threshold, :custom_props],
             name: :goals_pageview_config_unique
           )
    create unique_index(:goals, [:site_id, :display_name], name: :goals_display_name_unique)

    # ============================================================================
    # GOOGLE AUTH
    # ============================================================================
    create table(:google_auth) do
      add :email, :string, null: false
      add :property, :string
      add :refresh_token, :string, null: false
      add :access_token, :string, null: false
      add :expires, :naive_datetime, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:google_auth, [:site_id])
    create index(:google_auth, [:user_id])

    # ============================================================================
    # WEEKLY REPORTS
    # ============================================================================
    create table(:weekly_reports) do
      add :recipients, :string, default: "[]"
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:weekly_reports, [:site_id])

    # ============================================================================
    # MONTHLY REPORTS
    # ============================================================================
    create table(:monthly_reports) do
      add :recipients, :string, default: "[]"
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:monthly_reports, [:site_id])

    # ============================================================================
    # SHARED LINKS
    # ============================================================================
    create table(:shared_links) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :password_hash, :string
      add :segment_id, references(:segments, on_delete: :delete_all)

      timestamps()
    end

    create unique_index(:shared_links, [:slug])
    create unique_index(:shared_links, [:site_id, :name], name: :shared_links_site_id_name_index)
    create index(:shared_links, [:segment_id])

    # ============================================================================
    # SPIKE NOTIFICATIONS (traffic change notifications)
    # ============================================================================
    create table(:spike_notifications) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :threshold, :integer, null: false
      add :last_sent, :naive_datetime
      add :recipients, :string, default: "[]"
      add :type, :string, default: "spike"

      timestamps()
    end

    create unique_index(:spike_notifications, [:site_id, :type])

    # ============================================================================
    # SITE USER PREFERENCES
    # ============================================================================
    create table(:site_user_preferences) do
      add :pinned_at, :naive_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:site_user_preferences, [:user_id, :site_id])

    # ============================================================================
    # SHIELD RULES - IP
    # ============================================================================
    create table(:shield_rules_ip, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :inet, :string
      add :action, :string, default: "deny"
      add :description, :string
      add :added_by, :string

      timestamps()
    end

    create unique_index(:shield_rules_ip, [:site_id, :inet])
    create index(:shield_rules_ip, [:site_id, :updated_at])

    # ============================================================================
    # SHIELD RULES - PAGE
    # ============================================================================
    create table(:shield_rules_page, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :page_path, :string, null: false
      add :page_path_pattern, :string
      add :action, :string, default: "deny"
      add :added_by, :string

      timestamps()
    end

    create unique_index(:shield_rules_page, [:site_id, :page_path_pattern])
    create index(:shield_rules_page, [:site_id, :updated_at])

    # ============================================================================
    # SHIELD RULES - COUNTRY
    # ============================================================================
    create table(:shield_rules_country, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :country_code, :string, null: false
      add :action, :string, default: "deny"
      add :added_by, :string

      timestamps()
    end

    create unique_index(:shield_rules_country, [:site_id, :country_code])
    create index(:shield_rules_country, [:site_id, :updated_at])

    # ============================================================================
    # SHIELD RULES - HOSTNAME
    # ============================================================================
    create table(:shield_rules_hostname, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :hostname, :string, null: false
      add :hostname_pattern, :string
      add :action, :string, default: "allow"
      add :added_by, :string

      timestamps()
    end

    create unique_index(:shield_rules_hostname, [:site_id, :hostname_pattern])

    # ============================================================================
    # SUBSCRIPTIONS
    # ============================================================================
    create table(:subscriptions) do
      add :paddle_subscription_id, :string, null: false
      add :paddle_plan_id, :string, null: false
      add :update_url, :string, null: false
      add :cancel_url, :string, null: false
      add :status, :string, null: false
      add :next_bill_amount, :string, null: false
      add :next_bill_date, :date, null: false
      add :last_bill_date, :date
      add :currency_code, :string, null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:subscriptions, [:paddle_subscription_id])
    create index(:subscriptions, [:team_id])

    # ============================================================================
    # ENTERPRISE PLANS
    # ============================================================================
    create table(:enterprise_plans) do
      add :paddle_plan_id, :string, null: false
      add :billing_interval, :string, null: false
      add :monthly_pageview_limit, :integer, null: false
      add :site_limit, :integer, null: false
      add :team_member_limit, :string, default: "-1"
      add :features, :string, default: "[\"props\",\"stats_api\"]"
      add :hourly_api_request_limit, :integer, null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:enterprise_plans, [:team_id])

    # ============================================================================
    # TEAM MEMBERSHIPS
    # ============================================================================
    create table(:team_memberships) do
      add :role, :string, null: false
      add :is_autocreated, :boolean, default: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:team_memberships, [:team_id, :user_id])
    create unique_index(:team_memberships, [:user_id],
             where: "role = 'owner' and is_autocreated = true",
             name: :one_autocreated_owner_per_user
           )
    create index(:team_memberships, [:team_id])
    create index(:team_memberships, [:user_id])

    # ============================================================================
    # TEAM INVITATIONS
    # ============================================================================
    create table(:team_invitations) do
      add :invitation_id, :string, null: false
      add :email, :string
      add :role, :string, null: false
      add :inviter_id, references(:users, on_delete: :delete_all), null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:team_invitations, [:invitation_id])
    create unique_index(:team_invitations, [:team_id, :email])
    create index(:team_invitations, [:inviter_id])
    create index(:team_invitations, [:team_id])
    create index(:team_invitations, [:email, :role])

    # ============================================================================
    # GUEST INVITATIONS
    # ============================================================================
    create table(:guest_invitations) do
      add :invitation_id, :string
      add :role, :string, null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :team_invitation_id, references(:team_invitations, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:guest_invitations, [:team_invitation_id, :site_id])
    create index(:guest_invitations, [:site_id])
    create index(:guest_invitations, [:team_invitation_id])
    create unique_index(:guest_invitations, [:invitation_id])

    # ============================================================================
    # GUEST MEMBERSHIPS
    # ============================================================================
    create table(:guest_memberships) do
      add :role, :string, null: false
      add :team_membership_id, references(:team_memberships, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:guest_memberships, [:team_membership_id, :site_id])
    create index(:guest_memberships, [:team_membership_id])
    create index(:guest_memberships, [:site_id])

    # ============================================================================
    # TEAM SITE TRANSFERS
    # ============================================================================
    create table(:team_site_transfers) do
      add :transfer_id, :string, null: false
      add :email, :string
      add :transfer_guests, :boolean, default: true
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :destination_team_id, references(:teams, on_delete: :delete_all)
      add :initiator_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:team_site_transfers, [:transfer_id])
    create unique_index(:team_site_transfers, [:destination_team_id, :site_id])
    create unique_index(:team_site_transfers, [:email, :site_id])

    # ============================================================================
    # TEAM MEMBERSHIP USER PREFERENCES
    # ============================================================================
    create table(:team_membership_user_preferences) do
      add :consolidated_view_cta_dismissed, :boolean, default: false
      add :sort_index_options, :map
      add :team_membership_id, references(:team_memberships, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:team_membership_user_preferences, [:team_membership_id])

    # ============================================================================
    # USER SESSIONS
    # ============================================================================
    create table(:user_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :device, :string, null: false
      add :last_used_at, :naive_datetime, null: false
      add :timeout_at, :naive_datetime, null: false

      timestamps(updated_at: false)
    end

    create index(:user_sessions, [:user_id])
    create index(:user_sessions, [:timeout_at])
    create unique_index(:user_sessions, [:token])

    # ============================================================================
    # TOTP RECOVERY CODES
    # ============================================================================
    create table(:totp_recovery_codes) do
      add :code_digest, :binary, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create index(:totp_recovery_codes, [:user_id])

    # ============================================================================
    # EMAIL ACTIVATION CODES
    # ============================================================================
    create table(:email_activation_codes) do
      add :code, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :issued_at, :naive_datetime, null: false
    end

    create unique_index(:email_activation_codes, [:user_id])

    # ============================================================================
    # PLUGINS API TOKENS
    # ============================================================================
    create table(:plugins_api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :hint, :string, null: false
      add :description, :string, null: false
      add :last_used_at, :naive_datetime

      timestamps()
    end

    create index(:plugins_api_tokens, [:site_id, :token_hash])

    # ============================================================================
    # SEGMENTS
    # ============================================================================
    create table(:segments) do
      add :name, :string, null: false
      add :type, :string, null: false, default: "personal"
      add :segment_data, :string, null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :owner_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:segments, [:site_id])
    create index(:segments, [:owner_id])

    # ============================================================================
    # TRACKER SCRIPT CONFIGURATION
    # ============================================================================
    create table(:tracker_script_configuration, primary_key: false) do
      add :id, :string, primary_key: true
      add :installation_type, :string
      add :track_404_pages, :boolean, default: false
      add :hash_based_routing, :boolean, default: false
      add :outbound_links, :boolean, default: false
      add :file_downloads, :boolean, default: false
      add :revenue_tracking, :boolean, default: false
      add :tagged_events, :boolean, default: false
      add :form_submissions, :boolean, default: false
      add :pageview_props, :boolean, default: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:tracker_script_configuration, [:site_id])
    create index(:tracker_script_configuration, [:updated_at])

    # ============================================================================
    # ANNOTATIONS
    # ============================================================================
    create table(:annotations) do
      add :note, :string, null: false
      add :type, :string, null: false, default: "personal"
      add :datetime, :utc_datetime, null: false
      add :granularity, :string, null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :owner_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:annotations, [:site_id])
    create index(:annotations, [:owner_id])

    # ============================================================================
    # SITE IMPORTS
    # ============================================================================
    create table(:site_imports) do
      add :start_date, :date, null: false
      add :end_date, :date, null: false
      add :source, :string, null: false
      add :status, :string, null: false
      add :legacy, :boolean, default: true
      add :has_scroll_depth, :boolean, default: false
      add :label, :string
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :imported_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:site_imports, [:site_id, :start_date])
    create index(:site_imports, [:imported_by_id])

    # ============================================================================
    # PENDING STATS DELETIONS
    # ============================================================================
    create table(:pending_stats_deletions) do
      add :site_id, :integer, null: false
      add :reason, :string, default: "user_request"

      timestamps()
    end

    create index(:pending_stats_deletions, [:reason])

    # ============================================================================
    # FUNNELS (EE)
    # ============================================================================
    create table(:funnels) do
      add :name, :string, null: false
      add :strict_order, :boolean, default: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:funnels, [:name, :site_id], name: :funnels_name_site_id_index)

    # ============================================================================
    # FUNNEL STEPS (EE)
    # ============================================================================
    create table(:funnel_steps) do
      add :step_order, :integer, null: false
      add :funnel_id, references(:funnels, on_delete: :delete_all), null: false
      add :goal_id, references(:goals, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:funnel_steps, [:goal_id, :funnel_id],
             name: :funnel_steps_goal_id_funnel_id_index
           )

    # ============================================================================
    # AUDIT ENTRIES (EE)
    # ============================================================================
    create table(:audit_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :entity, :string, null: false
      add :entity_id, :string, null: false
      add :meta, :string, default: "{}"
      add :change, :string, default: "{}"
      add :user_id, :integer, default: 0
      add :team_id, :integer, default: 0
      add :datetime, :naive_datetime, null: false
      add :actor_type, :string, default: "system"
    end

    create index(:audit_entries, [:entity])
    create index(:audit_entries, [:entity_id])
    create index(:audit_entries, [:user_id])
    create index(:audit_entries, [:team_id])
    create index(:audit_entries, [:datetime])

    # ============================================================================
    # TRIAL PROSPECTS (EE)
    # ============================================================================
    create table(:trial_prospects) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :estimated_monthly, :integer, null: false
      add :observed_days, :integer, null: false
      add :first_data_day, :date, null: false
      add :kind, :string, null: false
      add :forced_by, :string, default: "[]"
      add :pageview_limit, :integer
      add :over_top_tier, :boolean, default: false
      add :estimated_mrr, :integer
      add :computed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:trial_prospects, [:team_id])
    create index(:trial_prospects, [:estimated_mrr])

    # ============================================================================
    # SALTS
    # ============================================================================
    create table(:salts) do
      add :salt, :binary, null: false

      timestamps(updated_at: false)
    end

    # ============================================================================
    # INTRO EMAILS
    # ============================================================================
    create table(:intro_emails) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :timestamp, :naive_datetime
    end

    # ============================================================================
    # FEEDBACK EMAILS
    # ============================================================================
    create table(:feedback_emails) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :timestamp, :naive_datetime, null: false
    end

    # ============================================================================
    # SENT WEEKLY REPORTS (renamed from sent_email_reports)
    # ============================================================================
    create table(:sent_weekly_reports) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :year, :integer
      add :week, :integer
      add :timestamp, :naive_datetime
    end

    # ============================================================================
    # SETUP HELP EMAILS
    # ============================================================================
    create table(:setup_help_emails) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :timestamp, :naive_datetime
    end

    create index(:setup_help_emails, [:site_id, :timestamp])

    # ============================================================================
    # SETUP SUCCESS EMAILS
    # ============================================================================
    create table(:setup_success_emails) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :timestamp, :naive_datetime
    end

    create index(:setup_success_emails, [:site_id, :timestamp])

    # ============================================================================
    # CREATE SITE EMAILS
    # ============================================================================
    create table(:create_site_emails) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :timestamp, :naive_datetime
    end

    create index(:create_site_emails, [:user_id, :timestamp])

    # ============================================================================
    # CHECK STATS EMAILS
    # ============================================================================
    create table(:check_stats_emails) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :timestamp, :naive_datetime
    end

    create index(:check_stats_emails, [:user_id, :timestamp])

    # ============================================================================
    # SENT RENEWAL NOTIFICATIONS
    # ============================================================================
    create table(:sent_renewal_notifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :timestamp, :naive_datetime
    end

    create index(:sent_renewal_notifications, [:user_id, :timestamp])

    # ============================================================================
    # SENT ACCEPT TRAFFIC UNTIL NOTIFICATIONS
    # ============================================================================
    create table(:sent_accept_traffic_until_notifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sent_on, :date, null: false
    end

    create unique_index(:sent_accept_traffic_until_notifications, [:user_id, :sent_on])

    # ============================================================================
    # PLANS (EE)
    # ============================================================================
    create table(:plans) do
      add :generation, :integer, null: false
      add :kind, :string, null: false
      add :features, :string, null: false
      add :monthly_pageview_limit, :integer, null: false
      add :site_limit, :integer, null: false
      add :team_member_limit, :integer, null: false
      add :volume, :string, null: false
      add :monthly_cost, :decimal
      add :monthly_product_id, :string
      add :yearly_cost, :decimal
      add :yearly_product_id, :string
    end

    # ============================================================================
    # HELP SCOUT CREDENTIALS (EE)
    # ============================================================================
    create table(:help_scout_credentials) do
      add :access_token, :binary, null: false

      timestamps()
    end

    # ============================================================================
    # HELP SCOUT MAPPINGS (EE)
    # ============================================================================
    create table(:help_scout_mappings) do
      add :customer_id, :string
      add :email, :string, null: false
      add :conversation_id, :string

      timestamps()
    end

    create unique_index(:help_scout_mappings, [:customer_id])
    create unique_index(:help_scout_mappings, [:conversation_id])
  end
end
