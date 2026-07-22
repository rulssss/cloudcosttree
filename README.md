# CloudCostTree

Estimate AWS infrastructure costs in a hierarchical tree — before you
apply. CloudCostTree reads your infrastructure-as-code (Terraform,
CloudFormation, Pulumi, a raw Terraform state file, or its own YAML/JSON)
and renders a cost breakdown, FinOps savings recommendations,
governance/cost policy checks, and a what-if simulator for testing changes
before they hit your cloud bill. AWS-only by design, CLI-only by design: no
multi-cloud, no hosted dashboard, no account required to see a cost tree.

```
$ cloudcosttree ./my-infra.tf

my-infra.tf ($842.13/mo)
├── aws_instance.web (t3.medium, us-east-1)          $30.37/mo
├── aws_db_instance.main (db.t3.large, Multi-AZ)     $263.52/mo
├── aws_ebs_volume.data (500GB, gp3)                 $40.00/mo
└── ...

💡 FinOps: aws_instance.web is oversized for its CPU utilization — consider t3.small ($15.18/mo, saves $15.19/mo)
```

## Table of contents

- [Install](#install)
- [Commands](#commands)
- [Input formats](#input-formats)
- [Supported AWS resources](#supported-aws-resources)
- [FinOps recommendations](#finops-recommendations)
- [Real usage volume — `--usage` file (every plan)](#real-usage-volume---usage-file)
- [Real Reserved Instance savings (Pro)](#real-reserved-instance-savings)
- [Usage-aware FinOps — `--with-usage` (Pro)](#usage-aware-finops---with-usage)
- [What-if simulator](#what-if-simulator)
- [Policies](#policies)
- [History](#history)
- [Exports](#exports)
- [CI/CD](#cicd)
- [VS Code extension](#vs-code-extension)
- [Free vs Pro](#free-vs-pro)
- [Architecture](#architecture)
- [License](#license)

## Install

CloudCostTree is meant to be installed as the **VS Code extension** (see
[VS Code extension](#vs-code-extension) below) or via the `cloudcosttree`
CLI binary directly — not by cloning this repository.

```sh
# macOS / Linux
curl -fsSL https://cloudcosttree.com/install.sh | sh
```

```powershell
# Windows (PowerShell)
irm https://cloudcosttree.com/install.ps1 | iex
```

Installs the binary matching your OS/CPU into a folder you own (`~/.local/bin`
on macOS/Linux, `%LOCALAPPDATA%\cloudcosttree\bin` on Windows) — no admin/
sudo needed — and adds it to your `PATH` automatically if it isn't already
there. To install by hand instead, grab a binary directly from
[cloudcosttree releases](https://github.com/rulssss/cloudcosttree/releases).

The CLI is fully self-contained: `data/prices.json` (the bundled price
catalog) travels with it, so a plain `analyze`/`tree`/`diff` run needs no
AWS account or credentials at all. Only `update-prices` (fetches the
project's published catalog over HTTPS) and the Pro `--with-usage` flag
(your own AWS credentials) ever touch the network.

## Commands

```
cloudcosttree <infrastructure_file> [options]                       # tree view
cloudcosttree analyze <infrastructure_file> [what-if flags] [options] # what-if simulation, FinOps, policies
cloudcosttree diff <baseline_file> <current_file> [options]          # compare two states
cloudcosttree update-prices [options]                                # refresh the AWS price catalog (no AWS account)
cloudcosttree policy init|check|list|validate                        # governance/cost policies
cloudcosttree usage init                                             # scaffold a --usage volume-override file
cloudcosttree ci report|check|diff                                   # CI/CD-friendly output (see CI.md)
cloudcosttree history save|list|compare|delete                       # track cost over time
cloudcosttree license buy|activate|status                            # CloudCostTree Pro
```

Run `cloudcosttree --help` (or `<command> --help`) for the full flag
reference — every command documents its own options in detail. The three
report-producing commands (`tree` via the bare form, `analyze`, `diff`)
all share the same general options:

| Flag | Meaning |
|---|---|
| `-prices <path>` | AWS price catalog JSON (default: `data/prices.json`) |
| `-params <path>` | CloudFormation parameter overrides in JSON |
| `-d` / `--detailed` | Show Hour/Week/Month breakdown (tree mode) |
| `--baseline <path>` | Baseline file for `diff` |
| `--policies <path>` | Governance/cost policies to check (falls back to `./policies.yaml`, then `~/.cloudcosttree/policies.yaml`) |
| `--usage <path>` | Declare real expected monthly traffic for request/GB/event-billed resources (Lambda, SQS, ...) — see below. Every plan, no AWS account needed |
| `--include-governance` | Also show governance-only FinOps findings (naming/tags) alongside real savings |
| `--with-usage` | (`analyze` only, **Pro**) enrich with real CloudWatch utilization + live Spot pricing — see below |
| `--export <format>[:path]` | Write a report in `md`/`csv`/`json`/`html`/`pr-comment` (omit `:path` to print to stdout) |

## Input formats

Auto-detected regardless of file extension:

- This tool's own YAML/JSON schema (see `examples/aws-basic.yaml`) — the
  only format that can carry `resource_id`/`arn` by hand for `--with-usage`
  testing without a real Terraform state.
- Terraform (`.tf`, evaluated via a live `terraform plan` against whatever
  backend the config uses).
- A raw Terraform state file (`.tfstate`) — no `terraform` binary or live
  plan needed, since the state is already a snapshot of deployed values.
- A CloudFormation template (`--params` for parameter overrides).
- A Pulumi stack export (`pulumi stack export`).
- A Terragrunt root directory — every unit's own plan is evaluated and the
  output is grouped by stack automatically (tree/diff/what-if/CSV all
  render one heading per Terragrunt unit); see `examples/terragrunt-demo/`.

## Supported AWS resources

Priced natively (own `resource_hourly`/dimension entry, not a heuristic
fallback): EC2 instances (with root EBS volume, OS multiplier), RDS
instances and RDS Cluster/Aurora (Multi-AZ, provisioned IOPS, backup
retention), standalone EBS volumes (gp2/gp3/io1/io2, provisioned IOPS and
throughput, snapshots), S3 buckets, EFS file systems, DynamoDB tables
(provisioned RCU/WCU with table-class multiplier, or on-demand), NAT
Gateway (fixed rate + data processed), Elastic IPs, ELB/ALB/NLB/GWLB, EKS
clusters, ElastiCache, VPN Gateway/Connection, Transit Gateway VPC
attachments, VPC Interface Endpoints, Redshift, Kinesis (Streams and
Firehose), ECS/Fargate services and task definitions, RDS Proxy, Lambda
(invocations + GB-seconds), CloudFront, CloudWatch (Logs ingestion, custom
metrics), API Gateway, GuardDuty, Security Hub, Config, CloudTrail, SQS,
SNS, Route 53 (hosted zone, health check), KMS, Secrets Manager.

Lambda, SQS, SNS, API Gateway, CloudFront(_distribution), GuardDuty,
Security Hub, Config, CloudTrail, and Kinesis Firehose are billed by AWS
purely per-request/GB/event, with no fixed capacity charge Terraform (or
any IaC format) could declare instead — this tool's per-unit rate for
every one of them is always real (freshly fetched from the AWS Price List
API), but the *volume* multiplied against it is a documented default
assumption unless you declare a real one — see
[Real usage volume](#real-usage-volume---usage-file) below. Lambda's
memory size is the one exception that's always real with no extra
step: it's a normal Terraform attribute (`memory_size`), read
automatically.

## FinOps recommendations

Every dollar figure is computed by re-pricing the actual resource against
the same price catalog used for the cost tree — never a flat guessed
percentage. Rules run against *declared* configuration by default (no
telemetry needed, no AWS account needed):

- **gp2 → gp3** (EBS and RDS/RDS Cluster storage) — gp3 is cheaper per GB
  and already bundles 3000 IOPS / 125MB/s throughput.
- **Provisioned IOPS (io1/io2) → gp3** — when provisioned IOPS are at or
  below gp3's bundled baseline.
- **Previous-generation instance type** (t2→t3, m4→m5, c4→c5, r4→r5,
  m3/c3/r3→…5) — same size class, cheaper and faster, across EC2/RDS/
  ElastiCache.
- **RDS Multi-AZ** — flags the doubled compute cost, asking you to confirm
  HA is genuinely needed.
- **RDS backup retention above 30 days** — re-priced at the 30-day cap.
- **NAT Gateway, low traffic** — compares the fixed hourly rate against a
  `t3.micro` NAT instance when monthly data processed is under 15GB.
- **DynamoDB provisioned, high capacity** — suggests on-demand when
  combined RCU+WCU is high, re-priced exactly (no RCU/WCU charge on-demand).
- **EC2 fleet without an Auto Scaling Group** — a `count > 1` resource with
  no ASG settings; informational (elasticity, not a quantified saving).
- **Reserved Instance / Savings Plan candidate** — steady-state (no
  autoscaling, default 24/7 hours), high-cost EC2/RDS. Quantified with a
  real $/mo figure on **Pro** when the catalog has a matching Reserved
  rate; Free/no-catalog-match sees the unquantified nudge. See
  [below](#real-reserved-instance-savings).
- **Governance nudges** (no dollar figure): missing tags/generic resource
  names, and Terraform's implicit `default_*` resources (default security
  group, VPC, route table, network ACL) left unmanaged. Shown standalone
  only when there's no real cost saving elsewhere (condensed, one line per
  issue), or always alongside cost recommendations with
  `--include-governance`.

Only shown when `--with-usage` (**Pro**) actually fetched real telemetry —
never a guess: **real CPU-based right-sizing** and **live Spot pricing**;
see [below](#usage-aware-finops---with-usage).

Display policy: cost recommendations always come first, ranked by impact
(top 3 on Free, top 15 on Pro). If there's no real economic saving
anywhere, the cost list is dropped entirely in favor of a condensed
governance nudge, so a "nothing to save" report never goes silent or lists
a dozen near-identical low-value findings.

## Real usage volume (`--usage` file)

```
cloudcosttree usage init                                    # scaffold usage.yaml
cloudcosttree ./my-infra.tf --usage usage.yaml
```

Available on **every plan** — no AWS account needed. Lambda, SQS, SNS, API
Gateway, CloudFront(_distribution), GuardDuty, Security Hub, Config,
CloudTrail, and Kinesis Firehose are billed by AWS purely per-request/GB/
event; nothing in a Terraform/CloudFormation/Pulumi declaration says how
much traffic one of them will actually get, so by default this tool prices
them against a documented, conservative assumption (1,000,000 requests/
month, etc.). A `--usage` file — the same idea as Infracost's usage file —
lets you declare the real number you actually expect, keyed by the
resource's Terraform address:

```yaml
version: "1.0"
resources:
  aws_lambda_function.api:
    monthly_invocations: 5000000
    avg_duration_ms: 250
  aws_sqs_queue.jobs:
    monthly_requests: 2000000
  aws_cloudfront_distribution.cdn:
    monthly_gb: 500
```

No file, or no entry for a given resource, changes nothing — the
documented assumed volume applies exactly as it always has, so this is
purely additive. Lambda's `memory_size` is priced for real regardless of
whether you use this file at all (Terraform already declares it); a
`--usage` entry additionally lets you correct the invocation count and
average duration, the two inputs Terraform genuinely can't know. Run
`cloudcosttree <file>` without `--usage` and CloudCostTree tells you
directly, on that same run, when a shown figure still rests on the
assumed default rather than a real number — the disclosure lives next to
the number itself, not just in this README.

On **Pro**, `--with-usage` (below) goes one step further for Lambda
specifically: it replaces even a `--usage` file's declared volume with
what a *real, already-deployed* function's CloudWatch metrics show it
actually did.

## Real Reserved Instance savings

`ruleReservedCapacityCandidate`'s "this looks like a Savings Plan / Reserved
Instance candidate" nudge is quantified with a real dollar figure whenever
the price catalog has a 1-year, no-upfront Reserved Instance rate for the
resource's EC2 instance type or RDS instance class (refreshed by the same
`update-prices`/`generate-prices` pipeline as on-demand rates — no extra AWS
account or credentials needed to see it, since the rate ships in the
public, published catalog). Savings Plans themselves aren't priced (no
public per-instance-type Savings Plan rate to query) — only the Reserved
Instance figure is ever quantified.

This is a **CloudCostTree Pro** feature: Free always sees the original,
unquantified nudge, even when the catalog does have a matching rate.

## Usage-aware FinOps (`--with-usage`)

```
cloudcosttree analyze ./my-infra.tf --with-usage
```

A **CloudCostTree Pro**, opt-in flag that calls your own read-only AWS
credentials (the default credential chain: env vars, a shared profile, SSO,
or an EC2/ECS/Lambda instance role) to replace two guesses with real
numbers, for resources this tool can resolve a real AWS resource ID for — a
`.tfstate` file, or a `terraform show -json` plan against already-applied
infrastructure. A brand-new resource being `create`d for the first time has
no real ID yet and is silently skipped for this enrichment (the rest of the
report is unaffected).

- **Real CPU-based right-sizing** — pulls each EC2/RDS/RDS Cluster
  resource's actual average CPU utilization from CloudWatch
  (`CPUUtilization`, 14-day lookback) and, when it's genuinely idle
  (under 10% average), recommends one size down within the same instance
  family/generation (e.g. `m5.xlarge` → `m5.large`) with an exact repriced
  dollar delta — instead of guessing anything from the declared instance
  type alone.
- **Live EC2 Spot pricing** — pulls the current Spot price
  (`ec2:DescribeSpotPriceHistory`, Linux/UNIX) for every distinct EC2
  instance type in your infrastructure and quotes the real
  on-demand-vs-Spot delta. Interruption risk is always called out in the
  message (Spot capacity can be reclaimed with two minutes' notice) — this
  tool has no way to know if your workload tolerates that, so it never
  hides the tradeoff.
- **Real Lambda cost correction** — unlike the two recommendations above,
  this corrects the cost tree's own headline number, not just a FinOps
  suggestion alongside it. For a Lambda function CloudWatch has data for,
  its real `Invocations` (14-day total, scaled to a monthly rate) and
  average `Duration` replace whatever a `--usage` file declared, or the
  assumed default — the same real-vs-guessed gap
  [above](#real-usage-volume---usage-file), just backed by measurement
  instead of a declaration. EC2/RDS CloudWatch data stays
  recommendation-only, deliberately: an EC2 instance's on-demand rate is
  already a hard catalog fact, not a volume guess the way Lambda's
  declared cost is.

Needs `cloudwatch:GetMetricData` and `ec2:DescribeSpotPriceHistory` IAM
permissions. A missing-credentials or missing-permission problem is
reported with an actionable message (not a raw SDK stack trace) and never
fails the run — the rest of the report still renders normally without the
extra recommendations. On Free, `--with-usage` is accepted but ignored
(prints a one-line upgrade note; the rest of the run is completely
unaffected). Deliberately **not** available during a `--<flag>` what-if
simulation: real CloudWatch data belongs to the resource as it exists
today, not to a hypothetically-resized simulated version of it.

## What-if simulator

```
cloudcosttree analyze ./my-infra.tf --target aws_instance.web --instance-type m5.large
```

Simulates a change to one resource (`--target <address or name>`) and shows
the before/after cost, without touching your Terraform code. Every
declared, priced attribute has a matching flag — `--instance-type`/
`--instance-class`, `--os`, `--region`, `--count`, `--auto-scaling-min`/
`--auto-scaling-max`, `--root-volume-size`/`--root-volume-type` (EC2),
`--volume-size`/`--volume-type` (EBS), `--multi-az`/`--no-multi-az`,
`--rds-backup-retention`, `--allocated-storage`, `--iops`, `--throughput`,
`--snapshot-size`, `--nat-data`, `--nat-type`, `--data-out`/`--data-in`,
`--elastic-ips`, `--dynamo-rcu`/`--dynamo-wcu`/`--dynamo-mode`,
`--table-class`, `--lb-type`/`--lb-scheme`, `--retention-days`,
`--hours-per-month`, and more — run `cloudcosttree analyze --help` for the
complete, resource-scoped list.

## Policies

Define governance and cost rules in a `policies.yaml` (see the one at the
repo root for a live example) and check them against any tree/analyze/diff
run with `--policies`, or as their own command group:

```
cloudcosttree policy check ./my-infra.tf --policies policies.yaml
cloudcosttree policy init      # scaffold a commented, ready-to-run policies.yaml
cloudcosttree policy validate  # check syntax without evaluating anything
cloudcosttree policy list      # show every policy that would apply
```

Condition language (evaluated per-resource):

| | |
|---|---|
| Fields | any resource attribute (`instance_type`, `monthly_cost`, `region`, `size_gb`, `multi_az`, `is_generic_name`, …) or a tag via `tags.<Key>` |
| Logic | `and`, `or`, `not` |
| Comparisons | `==` `!=` `<` `<=` `>` `>=` |
| Membership | `in [...]` / `not in [...]` |
| Presence | `<field> exists` (e.g. `tags.Owner exists`) |

`resource_type` (optional) restricts a policy to one resource type; omit it
to check every resource. `action` is `warn` \| `error` \| `deny` — the
latter two fail the run with a non-zero exit code, which is what CI/CD
gating builds on. `severity` (`critical`/`high`/`medium`/`low`) controls
display order and the icon shown in the violations section.

Policy evaluation (cost guardrails, tag/FinOps rules) is a **CloudCostTree
Pro** feature — see [Free vs Pro](#free-vs-pro). On Free, `policy check`
requires an upgrade, and policy checks embedded in tree/analyze/diff/ci
silently evaluate zero policies (the cost report stays informational;
nothing can fail a build).

## History

```
cloudcosttree history save ./my-infra.tf --tag prod-2026-07
cloudcosttree history list
cloudcosttree history compare <name-or-id> <name-or-id>
cloudcosttree history delete <name-or-id>
```

Snapshots a cost tree locally (no account, no upload) so you can compare
cost over time the same way `diff` compares two files. 180-day retention,
auto-pruned — disk hygiene, not a plan limit; identical on Free and Pro.

## Exports

`--export <format>[:path]` on `tree`/`analyze`/`diff` (omit `:path` to
print to stdout, pipeable): `md`, `csv`, `json`, `html`, or `pr-comment`
(GitHub-flavored, what `ci diff` posts to a PR). Unlimited on both tiers.

## CI/CD

See [CI.md](CI.md) for the full guide — GitHub Actions (a ready-to-use
composite action, published at
[`rulssss/cloudcosttree`](https://github.com/rulssss/cloudcosttree) so it
only ever downloads a prebuilt binary, never the private source repo),
GitLab CI, and Azure Pipelines, JSON/Markdown output, and PR annotations.
The dedicated `ci` command group (`report` never fails the build;
`check`/`diff` fail on a blocking policy violation) shares Free's
1,000-runs/month quota across a repo's pipelines (tracked per-repo
server-side on GitHub Actions, since a fresh runner every job has nothing
local to count against); Pro is unlimited, confirmed live on every run via
a `license-key` input — no per-machine activation seat is spent doing this,
unlike the normal desktop `license activate` flow.

## VS Code extension

[vscode-extension/](vscode-extension/) adds an in-editor cost tree,
what-if panel, and diff view on top of the same CLI (every number comes
from a real `cloudcosttree analyze --export json:-` call, no re-implemented
pricing/parsing logic) — see its own README for setup.

## Free vs Pro

Free is a generous, unlimited cost-visibility tool for local use — Pro adds
CI/CD scale, the ability to actually enforce governance, real-dollar
Reserved Instance/Spot pricing, and usage-aware right-sizing.

| | Free | Pro ($14.99/mo) |
|---|---|---|
| Analyses (tree/analyze/diff) | Unlimited | Unlimited |
| What-if simulations | Unlimited | Unlimited |
| Exports (md/csv/json/html/pr-comment) | Unlimited | Unlimited |
| History (`history save`/`list`/`compare`) | Unlimited, 180-day retention | Unlimited, 180-day retention |
| FinOps recommendations shown | Top 3 by impact | Top 15 by impact |
| Real usage volume for request/GB/event-billed resources (`--usage` file: Lambda, SQS, SNS, ...) | Included | Included |
| Real Reserved Instance $ savings | Unquantified nudge only | Real 1yr-no-upfront $/mo figure |
| Usage-aware FinOps (`--with-usage`: CloudWatch right-sizing + live Spot pricing + real Lambda cost correction) | Not included | Included |
| CI/CD runs (`ci report`/`check`/`diff`) | 1,000/month | Unlimited |
| Cost guardrails & tag/FinOps policies (`policy check`, and policy enforcement inside tree/analyze/diff/ci) | Not included — cost data stays informational | Unlimited, can fail a build on violation |
| Cloud provider support | AWS | AWS |
| VS Code extension | Included | Included |

History's 180-day retention (auto-pruned locally, see `pkg/history`) is disk
hygiene, not a plan limit — it's the same on both tiers. Custom/negotiated
price books aren't implemented yet on either plan.

```
cloudcosttree license status     # see your current plan and usage
cloudcosttree license buy        # upgrade
cloudcosttree license activate <key>
```

Licensing is a signed, local usage record (HMAC — a tamper *deterrent*, not
a defense against a determined binary patch) plus a small Cloudflare Worker
(`paddle-license-worker/`) that fronts Paddle for activation/validation —
Paddle has no public, unauthenticated License API of its own, so the Worker
holds the Paddle secret key and exposes the same activate/validate/
deactivate JSON envelope. See `pkg/license`.

## Architecture

```
cmd/cloudcosttree/   CLI entrypoint, flag parsing, Free/Pro gating (license_gate.go)
pkg/parser/          Terraform (plan + state), Terragrunt, CloudFormation, Pulumi → model.Infrastructure
pkg/model/           The shared Resource/Infrastructure schema every parser/renderer speaks
pkg/cost/            PriceCatalog + Calculator: prices.json → a resource's/tree's $/mo
pkg/pricing/         update-prices/generate-prices: AWS Price List API → prices.json
pkg/usagefile/       --usage file: local, declarative volume overrides (every plan)
pkg/usage/           --with-usage: live CloudWatch + EC2 Spot calls (Pro)
pkg/finops/          Savings-recommendation rules (declared-config rules + usage-aware rules)
pkg/policy/          Governance/cost policy DSL: parsing, condition evaluation, templates
pkg/tree/            Rendering: tree/comparison/what-if views, every export format
pkg/history/         Local cost-snapshot storage + comparison
pkg/ci/              CI/CD-shaped report/check/diff output
pkg/license/         Free/Pro state, quotas, license Worker client
paddle-license-worker/ Cloudflare Worker fronting Paddle for activation/validation (see above)
vscode-extension/    Thin UI layer over the CLI (no duplicated pricing/parsing logic)
```

`data/prices.json` is the one artifact that ties `pkg/pricing` (writer) and
`pkg/cost` (reader) together: a per-region snapshot of on-demand + (Pro)
Reserved Instance rates, refreshed periodically by this project's own
automation and fetched by end users as a plain public file — the only
CloudCostTree capability that needs an AWS account of its own is
`--with-usage`, and that account is always the end user's, never this
project's.

## License

Proprietary — all rights reserved. Not open source; no public
contribution/license grant is implied by this repository being readable.
