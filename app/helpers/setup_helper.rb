# Setup & API keys page: stepper, install snippets and key rows.
module SetupHelper
  STEP_TEXT = { done: "text-mint-300", current: "text-ink-50", pending: "text-ink-400" }.freeze
  STEP_MARKERS = {
    done: "bg-mint-500/20 border border-mint-400/50",
    current: "bg-iris-400 text-ink-50 font-semibold",
    pending: "border border-paper-600"
  }.freeze
  PLACEHOLDER_KEY = "YOUR_API_KEY".freeze
  SAMPLE_ENDPOINT = "https://errors.yourco.internal".freeze

  def setup_step_classes(step)
    "flex items-center gap-2 #{STEP_TEXT.fetch(step.state)}"
  end

  def setup_step_marker(step)
    tag.span step.done? ? "✓" : step.number,
      class: "w-6 h-6 rounded-full grid place-items-center text-[11px] #{STEP_MARKERS.fetch(step.state)}"
  end

  # The line between two steps is mint once the step before it is done.
  def setup_step_connector(previous_step)
    tag.li class: previous_step.done? ? "w-12 h-px bg-mint-400/40" : "w-12 h-px bg-paper-600", "aria-hidden": true
  end

  # Install snippets show the short masked key ("gs_live_9f2c…e81a"); the full
  # key is behind Reveal. Copy skips the masked key and takes a placeholder
  # instead, so a copied command never contains an unusable key.
  def install_key_hint(api_key)
    return PLACEHOLDER_KEY unless api_key

    safe_join [ tag.span(api_key.short_masked_token, data: { clipboard_skip: true }),
                tag.span(install_key_placeholder(api_key), hidden: true) ]
  end

  def install_key_placeholder(api_key)
    "YOUR_#{api_key.environment.upcase.tr('-', '_')}_KEY"
  end

  # Where the gem should send events: this instance (overridable for proxies).
  def instance_endpoint
    ENV.fetch("GOODSORCERY_PUBLIC_URL") { request.base_url }
  end

  # Hosted installs keep the gem's default endpoint; self-hosted ones point at this instance.
  def endpoint_config_line
    return tag.span(%(# config.endpoint = "#{SAMPLE_ENDPOINT}"  # self-hosted), class: "tok-c") if hosted?

    safe_join [ "config.endpoint     = ", tag.span(%("#{instance_endpoint}"), class: "tok-s") ]
  end

  def endpoint_env_line
    return if hosted?

    safe_join [ "\nGOODSORCERY_ENDPOINT=", tag.span(instance_endpoint, class: "tok-s") ]
  end

  def api_key_label(api_key)
    api_key.environment.humanize
  end

  # "Created 10 min ago by Philip · never used"
  def api_key_history(api_key)
    creator = api_key.created_by && " by #{api_key.created_by.first_name}"
    used = api_key.last_used_at ? "last used #{time_ago_compact(api_key.last_used_at)}" : "never used"
    "Created #{time_ago_compact(api_key.created_at)}#{creator} · #{used}"
  end
end
