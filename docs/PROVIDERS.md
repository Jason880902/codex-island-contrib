# Provider connections

Settings → Providers selects one or two distinct providers. A single provider
occupies the left slot. Picking the provider already in the other slot swaps
them; the central swap button does the same. Existing Claude/Codex visibility
preferences migrate automatically, and order persists across launches.

All providers use the same Rails, Ring, Grid, History, and Stepped views,
used/remaining preference, peek pills, and threshold alerts. A provider's data
selects the metrics; changing providers does not change the chart style.

## Codex limit windows

Codex charts follow the windows reported by the usage API, not the plan name.
A weekly-only response displays one quota in the provider column; Rails and History span its width, while Ring uses one empty-center gauge with an adjacent reading.
Two reported windows retain the 5h/week pair. The discovered window list survives
failed refreshes, so an offline request cannot bring back a removed 5h tile.
Zero-percent windows remain visible. Peek and alerts select the same available
window, and chart styles and history keys remain unchanged.

## Claude Enterprise credits

Enterprise accounts can report monthly `extra_usage` credits alongside or instead
of the five-hour and weekly windows. The app converts cent amounts to currency
units, keeps missing spend distinct from zero, and shows unlimited credit usage as an
amount rather than a quota percentage. Credit amounts use the API currency.
They describe credits consumed, not an invoice or an actual billed charge.

A missing `monthly_limit` is unknown; only an explicit `null` represents
unlimited credits. Incomplete credit readings are omitted.

Monthly credit limits are evaluated independently for threshold alerts. Reset
countdowns use only provider-supplied boundaries. Percentage-only history remains
available to charts but is not used to seed monthly spend after relaunch. A failed
refresh preserves a previous credit reading with the error shown beside it.

## Grok subscriptions

Sign in with the official Grok CLI (`grok login`) using your Grok subscription.
A grok.com browser login alone does not create the CLI session this integration
reads. Settings opens the CLI login when installed, or the official Grok Build
page when it is missing. After signing in, choose Refresh connection.

The adapter reads `$GROK_HOME/auth.json` (default `~/.grok/auth.json`) and requests
credit usage from the Grok CLI billing service. On expiry or HTTP 401, the app
runs `grok models` once to let the CLI
renew its session, then rereads credentials and retries. It never rotates or writes
the CLI's tokens itself. The credits response supplies the subscription percentage
and weekly or monthly period label. Unified billing accounts, or responses without
a usable percentage, also query the default billing endpoint for `used / monthlyLimit`.
On-demand spending is never substituted for included subscription quota. Missing
percentages remain unknown; a billing period alone is not interpreted as zero usage.

When a connected provider reports no readings, its column shows an actionable
empty state instead of an empty chart and reset timer. A successfully fetched
Free plan shows “No active subscription”; paid or unknown plans show “Usage
unavailable.” Both link to provider settings. Actual readings, including 0%,
remain visible regardless of the plan label. The Cost page reuses the same
subscription state when both cost windows are unavailable and contain no usage;
existing cost records remain visible.

## Google Antigravity

Sign in with the official `agy` CLI. The desktop app is not required and does
not need to be running. Settings opens `agy` in Terminal when installed, or the
official CLI installation page when missing. After signing in, choose Refresh
connection.

The adapter reads the CLI's macOS Keychain entry (`gemini` / `antigravity`) without
writing it. On expiry or HTTP 401, the app runs `agy models` once,
then rereads the Keychain and retries. The CLI owns token refresh and persistence.
These model-list commands run without a prompt, with closed stdin and a 25-second
timeout; they do not start an agent turn. Failed renewal is reported as a connection
error, and HTTP 403 is not treated as proof of logout. It resolves the signed-in account's project via
`loadCodeAssist`, then passes that project to `retrieveUserQuotaSummary`.
The account project isolates display preferences and quota history. A Gemini API
key alone is not treated as an Antigravity subscription login.

Gemini is the preferred default group when present; otherwise an available group
is selected deterministically. Reported five-hour and weekly windows take
precedence. Settings can select another model group, one or two metrics, their
order, and which displayed metric drives peek and alerts. Use defaults restores
the automatic selection. No five-hour window is invented for a weekly-only plan.

Preferences use account identity when supplied by the provider. Quota history
is stored under hashed account and metric identifiers; an unidentified session
does not write persistent quota history. A removed custom group stays unavailable
until the user selects another group or restores defaults.

## Limits

Subscription limits and local cost history are separate sources. Cost, Tokens,
Value, Trend, model breakdowns, and the activity grid use the same aggregation
and views for every provider. Local history covers records on this Mac, across
local CLI accounts; it is not an account-wide billing statement.

Antigravity reads `~/.gemini/antigravity-cli/conversations/*.db` using read-only
SQLite transactions, including committed WAL data while the CLI is running.
`gen_metadata` stores one protobuf `CortexStepGeneratorMetadata` per model call.
The reader takes usage and response model from `chat_model`, and joins its
`step_indices` to `steps.metadata.created_at`. Input and cache buckets are
already disjoint; output already includes thinking. Provider message IDs dedupe
copied/forked calls. Transcript files and their chunk copies are not summed.
No desktop process, status-line hook, or credential refresh is needed.

Grok reads timestamped prompt usage from persisted ACP `updates.jsonl` under
`$GROK_HOME/sessions` (default `~/.grok/sessions`). It normalizes full-input ACP
counts into uncached/cache buckets and deduplicates repeated prompt/model IDs.
Incomplete usage and records without timestamps or per-model counts are omitted
with a local-records notice. This path has fixture coverage; a real Grok session
with persisted usage is still needed to validate the installed CLI's format.

An absent record is shown as unknown, rather than zero spend. Unreadable or
incomplete histories surface a local-records notice instead of a green Synced
status. Unknown model prices retain token/activity data and show an unpriced
warning. Local summaries do not depend on quota login succeeding.

Dollar values estimate API-equivalent token cost, not subscription charges.
Gemini 3.6/3.7/3.8 Flash use the published standard token/cache rates, including
the 2027 introductory-price cutoff applied at the call timestamp. This excludes
cache storage, search/tool charges, and discounts. See [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).
The Value view uses the [US monthly AI Pro reference price](https://one.google.com/about/plans)
when that exact plan is detected; an unknown plan price is shown as unavailable.

Connections follow the existing 5/15/30-minute polling presets. A manual refresh
is available; Grok HTTP 429 responses enforce a 15-minute cooldown. Deselecting a
provider cancels its pending request, and swapping positions does not fetch.

Grok's CLI billing response and Antigravity's quota protocol can change.
Fixture tests cover parsing and selection; validating authentication requires a
signed-in CLI. Authenticated requests use HTTPS and do not follow redirects.

## Provider colors

Provider identity colors live in `Sources/Theme/Colors.swift` and are routed
through `IslandProvider.color` for marks, usage charts, cost charts, and peek.
These are CodexIsland display colors, not claims about official brand palettes.

| Provider | Color | Hex |
| --- | --- | --- |
| Claude | Terracotta | `#CC785C` |
| Codex | Sky blue | `#5AA8F0` |
| Grok | White | `#FFFFFF` |
| Antigravity | Lilac | `#B69CFF` |

Antigravity uses a separate hue from Codex so adjacent providers are recognizable
at a glance. Green, amber, and red remain reserved for status and alerts. Keep
provider names and distinct marks visible so identification never depends only
on color.

## Demo mode

`CODEXISLAND_DEMO=1` also supplies synthetic Grok and Antigravity cost totals,
cumulative trends, and overview token history. VALUE uses illustrative monthly
plan baselines ($30 and $19.99 respectively) only in demo mode. These fixtures
never write the real cost cache or establish live subscription prices.

## Kimi Code, Gemini CLI, and GLM

This fork adds three providers to the upstream 0.3.0 connection, chart, alert,
local-history, currency, and weekly-card flows. Choose any two in Settings →
Providers. Existing `MacIsland.slotLeft` / `slotRight` assignments migrate once;
upstream `selectedProviders` preferences take precedence.

### Kimi Code

Run `kimi login`, then refresh the connection. Credentials are read from
`$KIMI_CODE_HOME/credentials/kimi-code.json` (default `~/.kimi-code`). The app
never rotates tokens or writes CLI credentials. When the access token expires or the API returns 401, the app runs the official
`kimi login` command in a bounded background process. For an existing valid
refresh credential, this command invokes the CLI's `ensureFresh` path and exits
without user interaction. ACP `authenticate` only checks cached credentials and
is not a renewal command. After the CLI exits, the app rereads the credential
file and retries quota usage once. No Terminal window, agent session, or model
prompt is started. The self-contained CLI receives an empty child PATH so it
cannot run a browser opener; device-login fallback is detected and stopped.
Only then is Settings login required. CLI lookup includes
`$KIMI_CODE_HOME/bin/kimi` and `~/.kimi-code/bin/kimi`.

Local usage reads `sessions/**/wire.jsonl` under that same home and retains
turn-scoped `usage.record` entries only. Input, output, cache reads, and cache
writes remain separate. Cumulative session records are skipped. Token history
is durable even after source files are removed. Kimi subscription-only model
aliases without a published API price remain explicitly **unpriced**, rather
than inventing a zero-dollar API-equivalent value or a subscription invoice.

### Gemini CLI

Sign in with Google in the official `gemini` CLI, then refresh. The app reads
`~/.gemini/oauth_creds.json` (or `$GEMINI_CLI_HOME/.gemini/oauth_creds.json`),
resolves the account project with `loadCodeAssist`, and sends that project to
`retrieveUserQuota`. It does not invent a project, refresh OAuth credentials,
or substitute Flash/Pro model quotas for five-hour/weekly windows. Model quotas
and reset times follow the response; the plan comes from the reported tier.
API-key-only CLI authentication cannot provide a Google subscription quota.

Local usage supports legacy `session-*.json` conversations and current JSONL
records, including subagents, under `.gemini/tmp`. Repeated message IDs retain
one final turn. Cached input is subtracted from total input; thinking tokens
are added to output once. Session contents are read locally; only token counts,
model identifiers, timestamps, and usage record identifiers enter the ledger.

### GLM Coding Plan

Enter the Coding Plan API key in provider settings. New keys are stored in
macOS Keychain; saving removes the previous plaintext preference. Existing
fork preferences remain readable until the user saves a replacement. You can
also use `ZAI_API_KEY` or `GLM_API_KEY`. The configurable HTTPS base defaults to
`https://open.bigmodel.cn`; international users can choose `https://api.z.ai`.
`GLM_BASE_URL` overrides the saved base. Credentials are sent only to the
configured host's `/api/monitor/usage/quota/limit` endpoint. The parser keeps
reported request/token meters distinct and accepts numeric or string percentages
and ISO/Unix reset times. The quota response contract is fixture-tested; a live
GLM account has not been used to validate it.

GLM local usage comes from OpenCode (`zai`, `z-ai`, `zhipuai`, or
`zai-coding-plan`). OpenCode Google/Moonshot provider IDs also feed the Gemini
and Kimi local cost histories. Subscription quota and local token history are
independent, so local costs remain available without a quota login.

### Price references and limits

Dollar totals are standard text **API-equivalent estimates**, not subscription
bills. The upstream remote catalog takes precedence; new offline fallback rates
cover Gemini 2.5 text models, Gemini 3.1 Flash-Lite, and common GLM models.
Gemini 2.5 Pro applies its >200k input-context tier. Unknown models keep their
tokens and an unpriced warning. Tool fees, audio-specific rates, cache storage,
and subscription invoices are outside these estimates.

Published price sources checked on 2026-10-07:

- [Google Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Z.AI API pricing](https://docs.z.ai/guides/overview/pricing)
- [Kimi billing contract](https://platform.kimi.com/docs/pricing/chat)
- [Gemini CLI quota types](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/code_assist/types.ts)
- [Gemini CLI session recording](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingService.ts)

Run `bash scripts/test-coding-providers.sh` for the added fixture checks. Local
preview builds can disable Sparkle with `SU_FEED_URL= ./build.sh`, preventing an
upstream release from replacing the fork-specific integrations during testing.
