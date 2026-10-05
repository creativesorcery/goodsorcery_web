# Good Sorcery Error Tracker

## Standing guidelines (from the user, 2026-10-04)

1. **Don't build until told.** Make no app changes until the user explicitly says to start building. Discussion, questions and design talk are fine before then.
2. **How to build, once told:** use Opus with high effort, run as a workflow. Build the Rails app to match the approved UI design in `~/projects/goodsorcery/design` (`index.html` and `DESIGN.md`):
   - Flat pastel theme.
   - No deploy tracking, no keyboard shortcuts, no needs-attention callout.
   - Use the wording "Add a new app".
3. **Rails conventions, old-school style:** Hotwire (Turbo and Stimulus) and Action Cable. No single-page JavaScript framework.
4. **Stack (already scaffolded):** Ruby 4.0.7, Rails 8.1.4, Postgres, Tailwind. No Solid Queue, Solid Cache or Solid Cable.
   - Production: Sidekiq on Redis for jobs, Redis cache store, Redis for Action Cable.
   - Development: async jobs, memory store, async Action Cable.
5. **No service objects with a `call` method.** Whenever an object is needed, plain old Ruby objects or classes with descriptive, domain-named methods are welcome. Just don't write them service-call style. Otherwise prefer rich models and concerns, in old-school Rails style.
6. **Short methods, shallow conditionals.**
   - Keep methods short. 20 lines is a hard limit, and split well before that.
   - Avoid deeply nested conditionals.
   - A growing method is a sign that its distinct behaviors belong in separate, well-named classes, designed in an object-oriented way.
7. **Review every code change for security and performance.**
   - Performance: avoid N+1 queries, cache where possible, and design for high-rate error ingest.
   - Security: treat everything captured with an error as sensitive, since it may contain personal data such as emails and usernames. That covers stack traces, code references, request params, headers, session, user context, breadcrumbs and environment.
