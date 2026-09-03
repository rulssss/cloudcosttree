# CloudCostTree

Understand, question, and experiment with what your AWS infrastructure
will cost, before you `terraform apply`. CloudCostTree reads your
infrastructure-as-code (Terraform, CloudFormation, Pulumi, a raw Terraform
state file, or its own YAML/JSON) and renders a cost breakdown, FinOps
savings recommendations, governance/cost policy checks, and a what-if
simulator for testing changes before they hit your cloud bill. AWS-only by
design, CLI-only by design: no multi-cloud, no hosted dashboard, no account
required to see a cost tree.

**CloudCostTree never applies infrastructure changes.** Every simulated
change (a what-if, `--optimize`, a scenario) is written to a new file or
directory (`--write-changes`), never to your original source, and never
executed against AWS. `guard` gates or warns before your own `terraform
apply` runs; it never runs one itself. Nothing this tool does can create,
modify, or destroy a real cloud resource.

```
$ cloudcosttree ./my-infra.tf

my-infra.tf ($842.13/mo)
├── aws_instance.web (t3.medium, us-east-1)          $30.37/mo
├── aws_db_instance.main (db.t3.large, Multi-AZ)     $263.52/mo
├── aws_ebs_volume.data (500GB, gp3)                 $40.00/mo
└── ...

💡 FinOps: aws_instance.web is oversized for its CPU utilization: consider t3.small ($15.18/mo, saves $15.19/mo)
```

## Quick start

```
$ cloudcosttree demo
```

No files of your own, no AWS account: `cloudcosttree demo` runs a small
bundled example through this tool's real pricing and FinOps engine (the
same rules and rates a real file gets), so there's something to see in
under a minute before pointing this at your own infrastructure. The VS
Code extension offers the same thing as a one-time "Run Demo" prompt on
first activation (dismissible, never runs automatically without a click;
see [VS Code extension](#vs-code-extension) below).

## Who this is for

CloudCostTree is for anyone who wants to question a plan's cost impact
before committing to it, not just see a number after the fact. That
fits an individual estimating their own AWS bill just as well as it fits
a company's platform, DevOps, or FinOps team checking infrastructure-as-code
as part of their normal review workflow, backed by real breadth of
coverage, not a narrow calculator. Today that means AWS, where it prices
~118 resource types with real, fetched-from-AWS rates (see [Supported AWS
resources](#supported-aws-resources) below).

For context: AWS itself has 240+ services; everything this tool doesn't
price is either not a fixed-capacity "resource" a cost tree can represent
at all (most of AWS's usage-billed services: Textract, Rekognition, Step
Functions, and similar have no per-resource flat rate to price against,
only per-call/per-event billing), or just hasn't been mapped yet.

## Known limitations at a glance

The full picture lives in [Supported AWS resources](#supported-aws-resources)
and the sections below, but the short version: **AWS-only, no multi-cloud**;
an Auto Scaling Group using `mixed_instances_policy` stays unpriced from
declared config alone (`--with-usage` resolves it from real AWS data; see
below); CloudFormation input never carries a real post-apply
resource ID by itself (unlike Terraform/Pulumi input, which always does).
`--with-usage` enrichment needs the extra `--stack-name <name>` flag to
resolve one live, since a plain template has no state of its own to read it
from; and Amazon Managed Grafana isn't mapped: it bills per active
Viewer/Editor/Enterprise-Plugin user, and `aws_grafana_workspace` declares
no user count to price against at all. Everything else this tool doesn't
price is either genuinely free
(a VPC, a security group) or just hasn't been mapped yet; see below for the
full, honest list of what that covers and why. The [IAM policy
generator](#iam-policy-generator) has its own, separate coverage: 1644
resource types today, each with a real, correctly scoped `Action` list and
`Resource: "*"`. Narrowing `Resource` to the exact ARNs a deployment
declares — per-resource granularity — is a planned Pro capability, not
implemented yet. An unmapped resource type shows up as a clearly labeled
warning, never a silent gap.

## Table of contents

- [Quick start](#quick-start)
- [Who this is for](#who-this-is-for)
- [Known limitations at a glance](#known-limitations-at-a-glance)
- [Install](#install)
- [Commands](#commands)
- [Input formats](#input-formats)
- [Supported AWS resources](#supported-aws-resources)
- [FinOps recommendations](#finops-recommendations)
- [Real usage volume (`--usage` file, every plan)](#real-usage-volume---usage-file)
- [Custom price books (every plan)](#custom-price-books)
- [Real Reserved Instance savings (Pro)](#real-reserved-instance-savings)
- [Usage-aware FinOps (`--with-usage`, Pro)](#usage-aware-finops---with-usage)
- [Measured data transfer (`--flow-logs`, Pro)](#measured-data-transfer---flow-logs)
- [Reconcile with your real bill (`--reconcile`, Pro)](#reconcile-with-your-real-bill)
- [What CloudCostTree does not claim](#what-cloudcosttree-does-not-claim)
- [What-if simulator](#what-if-simulator)
- [Optimize (`--optimize`)](#optimize)
- [Policies](#policies)
- [Local apply guard (`guard`, Pro)](#local-apply-guard-guard)
- [Cost Score](#cost-score)
- [History](#history)
- [Exports](#exports)
- [CI/CD](#cicd)
- [IAM policy generator (`iam`)](#iam-policy-generator)
- [VS Code extension](#vs-code-extension)
- [Free vs Pro](#free-vs-pro)
- [Architecture](#architecture)
- [License](#license)

## Install

CloudCostTree is meant to be installed as the **VS Code extension** (see
[VS Code extension](#vs-code-extension) below) or via the `cloudcosttree`
CLI binary directly, not by cloning this repository.

```sh
# macOS / Linux
curl -fsSL https://cloudcosttree.com/install.sh | sh
```

```powershell
# Windows (PowerShell)
irm https://cloudcosttree.com/install.ps1 | iex
```

Installs the binary matching your OS/CPU into a folder you own (`~/.local/bin`
on macOS/Linux, `%LOCALAPPDATA%\cloudcosttree\bin` on Windows), no admin/
sudo needed, and adds it to your `PATH` automatically if it isn't already
there. To install by hand instead, grab a binary directly from
[cloudcosttree releases](https://github.com/rulssss/cloudcosttree/releases).

Also available via a real package manager, same binary either way:

```sh
# Homebrew (macOS/Linux)
brew install rulssss/cloudcosttree/cloudcosttree
```

```sh
# apt (Debian/Ubuntu, amd64/arm64) -- one-time repo setup, then a normal apt install
curl -fsSL https://rulssss.github.io/cloudcosttree-apt/cloudcosttree-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/cloudcosttree-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/cloudcosttree-archive-keyring.gpg] https://rulssss.github.io/cloudcosttree-apt stable main" \
  | sudo tee /etc/apt/sources.list.d/cloudcosttree.list
sudo apt update && sudo apt install cloudcosttree
```

```sh
# pip (any OS with Python) -- a thin wrapper, downloads the same real binary on first run
pip install cloudcosttree
```

The CLI is fully self-contained: `data/prices.json` (the bundled price
catalog) travels with it, so a plain `analyze`/`tree`/`diff` run needs no
AWS account or credentials, and touches no network at all. The commands
that do touch the network, each opt-in: `update-prices` (fetches the
project's published catalog over HTTPS), the Pro `--with-usage` flag
(your own AWS credentials), `license buy`/`activate`/`status` (the
license service), and `--export slack:<https://...>` (POSTs to your own
Slack webhook URL, if you pass one).

The published catalog itself refreshes on a ~15-day cadence (a weekly cron
job that skips itself when `data/prices.json` is still fresh; see
`.github/workflows/update-prices.yml`), so a freshly-installed binary's
bundled rates are never more than ~2-3 weeks stale; run
`cloudcosttree update-prices` yourself at any time to force an immediate
refresh.

## Commands

```
cloudcosttree demo                                                   # bundled example, no files or AWS account needed
cloudcosttree <infrastructure_file> [options]                        # tree view
cloudcosttree analyze <infrastructure_file> [what-if flags] [options] # what-if simulation, FinOps, policies
cloudcosttree diff <baseline_file> <current_file> [options]          # compare two states
cloudcosttree update-prices [options]                                # refresh the AWS price catalog (no AWS account)
cloudcosttree policy init|check|list|validate                        # governance/cost policies
cloudcosttree usage init                                             # scaffold a --usage volume-override file
cloudcosttree ci report|check|diff                                   # CI/CD-friendly output (see CI.md)
cloudcosttree history save|list|trend|compare|delete|export|import   # track cost over time
cloudcosttree license buy|activate|status                            # CloudCostTree Pro
cloudcosttree guard -- terraform apply                               # local apply-time policy gate (not the CI Cost Guard workflow)
cloudcosttree iam <path> [--plan <planfile>] [--output text|json]    # least-privilege IAM policy this deployment needs, no AWS account
```

Run `cloudcosttree --help` (or `<command> --help`) for the full flag
reference: every command documents its own options in detail. The three
report-producing commands (`tree` via the bare form, `analyze`, `diff`)
all share the same general options:

| Flag | Meaning |
|---|---|
| `-prices <path>` | AWS price catalog JSON (default: `data/prices.json`) |
| `-params <path>` | CloudFormation parameter overrides in JSON |
| `-d` / `--detailed` | Show Hour/Week/Month breakdown (tree mode) |
| `--dry-parse` | (`tree` mode only) Validate the parser recognizes the file and report resource count/types, no pricing; see [Commands](#commands) below |
| `--baseline <path>` | Baseline file for `diff` |
| `--policies <path>` | Governance/cost policies to check (falls back to `./policies.yaml`, then `~/.cloudcosttree/policies.yaml`) |
| `--usage <path>` | Declare real expected monthly traffic for request/GB/event-billed resources (Lambda, SQS, ...); see below. Every plan, no AWS account needed |
| `--price-overrides <path>` | Apply your own negotiated/EDP discount on top of the published catalog; see [Custom price books](#custom-price-books) below. Every plan, no AWS account needed |
| `--include-governance` | Also show governance-only FinOps findings (naming/tags) alongside real savings |
| `--with-usage` | (`analyze` and `diff`, **Pro**) enrich with real CloudWatch utilization + live Spot pricing; see below. On `diff`, applied to the baseline and current file independently |
| `--stack-name <name>` | (`analyze` and `diff`, with `--with-usage`, CloudFormation input only, **Pro**) the deployed stack name, needed to resolve real resource IDs for a CloudFormation template; see below. On `diff`, the same value is used for both files |
| `--accounts <path>` | (`analyze` and `diff`, with `--with-usage`) multi-account role mapping; see [Multi-region and multi-account](#multi-region-and-multi-account---accounts) below |
| `--reconcile` | (`analyze` and `diff`, **Pro**) read what AWS actually billed over the last 14 days (Cost Explorer, your own read-only credentials) and show it next to the list-price estimate; see [Reconcile with your real bill](#reconcile-with-your-real-bill) below. Cost Explorer bills you $0.01/request, so results are cached ~12h. With `--accounts`, reads every distinct role and merges |
| `--reconcile-refresh` | (with `--reconcile`) ignore the cache and re-query Cost Explorer now |
| `--reconcile-days <n>` | (with `--reconcile`) lookback window, default 14. A window over 14 days drops to service-level resolution — per-instance data isn't kept past 14 days |
| `--cost-allocation-tag <key>` | (with `--reconcile`) also break the comparison down by this cost-allocation tag key. The tag must be activated in the AWS billing console or Cost Explorer returns nothing for it |
| `--flow-logs` | (`analyze`, **Pro**, implies `--with-usage`) read your existing VPC Flow Logs (CloudWatch Logs destination) to price the data transfer CloudWatch can't isolate: cross-AZ / inter-AZ, direct-to-internet egress from public-subnet instances, and inter-region egress; see [Measured data transfer](#measured-data-transfer---flow-logs) below. Never enables Flow Logs; the Logs Insights scan is billed by AWS at ~$0.005/GB |
| `--scenario <path>` | (`analyze` only) Simulate changes to several resources at once from a YAML file; see [What-if simulator](#what-if-simulator) below |
| `--optimize` | (`analyze` only) Auto-build and simulate a what-if scenario from the FinOps recommendations already shown, applying only the ones safe to apply mechanically; see [Optimize](#optimize) below |
| `--write-changes <dir>` | (`analyze` only, **Pro**) Write a what-if simulation's result to a new file/directory, never the original; see [What-if simulator](#what-if-simulator) below |
| `--export <format>[:path]` | Write a report in `md`/`csv`/`json`/`html`/`pr-comment`/`slack` (omit `:path` to print to stdout; a `slack:https://...` webhook URL posts directly instead) |

`--dry-parse` (`cloudcosttree <file> --dry-parse`) skips pricing entirely:
useful in CI as a fast "does this tool even understand this file" check
before paying for a slower step like a live `terraform plan`:

```
$ cloudcosttree ./my-infra.tf --dry-parse
✓ Parsed ./my-infra.tf
  Provider: aws
  Region:   us-east-1
  Resources: 2
    ebs                            1
    ec2                            1
```

## Input formats

Auto-detected regardless of file extension:

- This tool's own YAML/JSON schema (see `examples/aws-basic.yaml`), the
  only format that can carry `resource_id`/`arn` by hand for `--with-usage`
  testing without a real Terraform state.
- Terraform (`.tf`, evaluated via a live `terraform plan` against whatever
  backend the config uses). A real `provider "aws" { ... }` block means
  Terraform itself needs valid AWS credentials to plan at all (an STS
  `GetCallerIdentity` call, independent of this tool's own `--with-usage`
  flag/license tier). For a credential-free cost preview with no AWS
  account involved, point the provider at throwaway values instead:
  `access_key`/`secret_key = "demo"` plus `skip_credentials_validation`/
  `skip_requesting_account_id`/`skip_region_validation = true`. A `.tfstate`
  file (below) sidesteps this entirely, needing no provider or live plan.
- A raw Terraform state file (`.tfstate`), no `terraform` binary or live
  plan needed, since the state is already a snapshot of deployed values.
- A CloudFormation template (`--params` for parameter overrides).
- A CDK-synthesized template: run `cdk synth`, then point this tool at the
  result (`cdk.out/<StackName>.template.json`). No CDK-specific parsing
  exists or is needed: CDK emits standard CloudFormation, read through the
  exact same converter as a hand-written template; CDK's extra `Metadata`/
  `Transform`/`Outputs` keys and the synthetic `AWS::CDK::Metadata` resource
  it always injects are all handled already. See `examples/cdk-demo/`. One
  limitation carries over unchanged from plain CloudFormation: a property
  set via `Fn::GetAtt` (common in CDK's L2 constructs for cross-resource
  references, e.g. a security group ID from another construct) isn't
  resolved and reads as empty, the same as any other unresolved
  CloudFormation intrinsic (only a `{"Ref": "ParamName"}` against
  `--params`/`Parameters` is).
- A Pulumi stack export (`pulumi stack export`).
- A Terraform Cloud/Enterprise workspace's remote state, fetched live over
  the TFC/TFE API instead of a local file: `tfc://<org>/<workspace>` for
  app.terraform.io, or `tfe://<hostname>/<org>/<workspace>` for a
  self-hosted Terraform Enterprise install. Pass either in place of a file
  path to `tree`/`analyze`/`diff`/`ci`/`history save`/`policy check`. Auth is
  a Terraform Cloud/Enterprise API token in the `TFE_TOKEN` environment
  variable, the same variable `terraform login` and the official `go-tfe`
  client already use, so a shell or CI job already configured for the
  `terraform` CLI needs no new secret. The workspace's current state version
  is fetched and priced exactly like a local `.tfstate` file: no new
  parsing, just a new byte source. See `pkg/parser/tfc.go`.
- A Terragrunt root directory: every unit's own plan is evaluated and the
  output is grouped by stack automatically (tree/diff/what-if/CSV all
  render one heading per Terragrunt unit); see `examples/terragrunt-demo/`.
- An Atmos (Cloud Posse) stack directory: a root containing
  `atmos.yaml`/`atmos.yml`, with per-stack YAML under `stacks/` declaring
  `components.terraform.<name>.vars` for one or more real Terraform
  component modules under `components/terraform/<name>/`. **Requires
  CloudCostTree Pro**: on Free, pointing this tool at an Atmos root exits
  with an upgrade message before any parsing happens (a hard stop, not a
  degraded report, unlike every other Pro feature). When the `atmos` binary
  is in PATH, every stack/component pair's real `atmos terraform plan` is
  evaluated (Atmos's own config resolution correctly handles `import:`
  catalog/mixin inheritance) and grouped into stack sections exactly like
  Terragrunt; without the binary, falls back to a static, credential-free
  scan of each stack YAML file's own directly-declared vars (`import:` is
  not followed in this mode) merged over each component module's variable
  defaults. See `examples/atmos-demo/` for a minimal dev/staging/prod
  fixture, or `examples/atmos-demo-advanced/` for a larger, more realistic
  one: 7 components spanning 12 distinct billable AWS resource types
  across 4 stacks (dev, staging, and two prod regions), with a real
  multi-level `import:` hierarchy (a per-tier sizing catalog shared across
  stacks, plus per-region mixins).
- A rendered Kubernetes manifest: run `helm template ...` or `kustomize
  build ...` yourself, save the output to a file (or pipe it in), and point
  this tool at that, the same trust boundary CDK input already
  establishes above ("render it yourself, point this tool at the static
  result"): no `helm`/`kustomize` binary invocation happens inside this
  tool at all. AWS-only, not a multi-cloud move: every `Deployment`/
  `StatefulSet` document's real declared `resources.requests` (summed
  across every container, init containers excluded) is priced against real
  AWS Fargate per-vCPU/per-GB rates, same real-size pricing Terraform's own
  `aws_ecs_task_definition`/`aws_ecs_service` now get too (see below) — the
  fixed 0.25vCPU/0.5GB assumed baseline is now only `eks_fargate_profile`'s,
  since the real requested size is right there in
  the manifest. A declared request is rounded up to the nearest size AWS
  Fargate actually bills (its own published vCPU/memory combination table,
  never scaled linearly against an arbitrary value AWS would never accept).
  Every other kind (`Service`, `ConfigMap`, `Ingress`, `DaemonSet`, `Job`,
  `CronJob`, ...) is parsed and skipped, not shown at $0: a `Service`/
  `ConfigMap` genuinely has no separate compute cost of its own (same as a
  VPC or security group), while `DaemonSet`'s real pod count depends on
  live cluster node count (unknowable from a static manifest) and `Job`/
  `CronJob` have no steady "replicas" concept at all: real, disclosed
  gaps, not silently dropped resources. Pods scheduled onto EKS managed
  node group EC2 capacity instead of Fargate aren't priced either: bin-
  packing pods onto nodes is a real scheduling decision (affinity, taints)
  this tool has no way to reproduce without guessing, so it's out of scope
  entirely rather than a guessed approximation. Grouped by namespace
  (`metadata.namespace`, falling back to `default`) the same way
  Terragrunt/Atmos group by unit/stack. **Free**: no Pro gate, same tier
  as Terraform/Terragrunt.

## Supported AWS resources

Priced natively (own `resource_hourly`/dimension entry, not a heuristic
fallback): EC2 instances (with root EBS volume, OS multiplier), RDS
instances and RDS Cluster/Aurora (Multi-AZ, provisioned IOPS, backup
retention, including separate Aurora writer/reader instances, and Aurora
Serverless v2's `db.serverless` instance class priced against its real min
ACU, cross-referenced from the owning `aws_rds_cluster`'s
`serverlessv2_scaling_configuration` for Terraform input, falling back to an
assumed 0.5 ACU floor for CloudFormation/Pulumi input; Aurora Serverless
v1's own `engine_mode = "serverless"` + `scaling_configuration.min_capacity`
(read directly off the same `aws_rds_cluster` resource, since unlike v2's
it isn't split across a separate child instance) is priced the same way,
against its own real, separate SKU at half v2's per-ACU rate, falling back
to v1's real 1 ACU floor when `min_capacity` is unset), standalone
EBS volumes (gp2/gp3/io1/io2, provisioned IOPS and throughput, snapshots),
S3 buckets, EFS file systems, DynamoDB tables (provisioned RCU/WCU with
table-class multiplier, or on-demand; Global Tables' replicated write
capacity, a real, separate AWS charge billed per additional replica
region, on top of the table's own base WCU), NAT Gateway (fixed rate + data
processed), Transit Gateway (fixed per-attachment rate + data processed,
declarable via this tool's own schema the same way NAT Gateway's is),
Elastic IPs, ELB/ALB/NLB/GWLB, EKS clusters, AWS Verified
Access (priced per endpoint-hour, HTTP/HTTPS vs. non-HTTP `cidr` endpoints
at their real, different AWS rates), VPC Lattice (priced per associated
service-hour, the service network itself carries no separate AWS charge),
ElastiCache
(single-node and Redis/Memcached/Valkey replication groups, priced by
each node's real declared `node_type` × real node count — including
cluster-mode-enabled sharding's real `num_node_groups` ×
`(1 + replicas_per_node_group)` total, not just the cluster-mode-disabled
`num_cache_clusters` count — engine-aware since the same node type has a
genuinely different rate per engine; not a flat cache.t3.micro/Redis-only
representative rate) and ElastiCache
Serverless
(real per-engine ECPU-hour + GB-hour storage rates, Redis, Memcached, and
Valkey are each genuinely priced differently; AWS's own real metering
floors apply when `cache_usage_limits` isn't set: no ECPU minimum at all,
but a real 1GB/0.1GB storage minimum for non-Valkey/Valkey engines
respectively), VPN Gateway/Connection, Transit
Gateway VPC attachments, VPC Endpoints (priced by real declared
`vpc_endpoint_type`: Gateway endpoints, e.g. to S3/DynamoDB, correctly
price at a real $0, since AWS publishes no billing SKU for them at all;
Interface, Gateway Load Balancer, and Resource endpoints each get their own
real per-hour rate, multiplied by real declared `subnet_ids` count for
Interface/Gateway Load Balancer, one ENI billed per AZ; ServiceNetwork has
no confirmed real rate yet and is left unpriced), Redshift (priced by each
cluster's real declared `node_type` × `number_of_nodes`, defaulting to 1
node the same way Terraform's own schema does; not a flat ra3.large-only
representative rate), Kinesis (Streams
and Firehose), ECS/Fargate services and task definitions (Terraform: priced
by each Fargate task definition's own real declared `cpu`/`memory`, plus a
real per-GB-hour surcharge for any declared `ephemeral_storage.size_in_gib`
above the always-free 20GB baseline, multiplied by the service's real
`desired_count`, when `requires_compatibilities` is unambiguously
`["FARGATE"]`; falls back to the flat 0.25vCPU/0.5GB baseline for an
EC2-launch-type/mixed-compatibility task or for CloudFormation/Pulumi
input, which read `desired_count` but don't yet resolve the task
definition cross-reference), RDS Proxy, Lambda
(invocations + GB-seconds), CloudFront, CloudWatch (Logs ingestion, custom
metrics/alarms), API Gateway, GuardDuty, Security Hub, Config, CloudTrail,
SQS, SNS, Route 53 (hosted zone, health check, flat AWS-endpoint base rate
plus a real, separately-billed surcharge for each optional feature actually
declared: HTTPS, string matching, a fast 10s `request_interval`, and
`measure_latency`, each stacking independently at their own real rate;
resolver endpoint), Route 53 Application Recovery Controller (real flat
per-cluster hourly rate, `aws_route53recoverycontrolconfig_cluster` has no
capacity attribute of its own, matching AWS's own per-cluster-only billing),
AWS Firewall Manager (`aws_fms_policy`, real flat per-policy-per-Region
monthly rate, identical across every protection type per AWS's own
pricing, so no `security_service_policy_data.type` matching is needed; the
one documented exception, a $0 rate for accounts already subscribed to
Shield Advanced, can't be resolved from the resource alone and is priced at
the same real rate as every other policy type rather than guessed at $0),
KMS,
Secrets Manager, MSK (Kafka: priced by each broker's real declared
`instance_type` × `number_of_broker_nodes`, plus real per-broker EBS
storage; not a flat representative-instance rate), OpenSearch/Elasticsearch
(priced by each domain's real declared data-node `instance_type` ×
`instance_count`, plus its own real per-data-node EBS storage when
`ebs_options` declares one; dedicated master nodes and UltraWarm nodes are
each priced as their own real declared `instance_type` × count, not folded
into the data-node total), Amazon DocumentDB (real per-instance-class rate, not a flat
representative-instance figure; the cluster resource itself carries a real
backup-storage surcharge when `backup_retention_period` is declared, its own
separate rate from RDS's) and Neptune (cluster instances only, the cluster
resource itself has no separate AWS charge), Network Firewall (billed per
real declared `subnet_mapping` endpoint, not a flat single unit), Route53
Resolver Endpoint (billed per real declared `ip_address` block, not a flat
single unit), WAFv2 Web ACL, FSx for Windows File
Server (SSD, Single-AZ baseline rate × real declared `storage_capacity`,
same "real value when available, documented assumed-capacity floor
otherwise" treatment as FSx for Lustre/OpenZFS/NetApp ONTAP above), AWS Lightsail (priced per bundle, General Purpose Linux bundles
only), Amazon Lightsail Database (real per-bundle-tier monthly price:
micro/small/medium/large, High Availability priced separately at its own
real rate; only these 4 confirmed active tiers, AWS's own published
bundle list), Amazon WorkSpaces (`aws_workspaces_workspace`'s
`compute_type_name` × `running_mode`, benchmarked against a Windows,
AWS-Included-license configuration, the real OS/license actually billed
comes from an opaque `bundle_id` this tool can't resolve without a live
API call, same class of gap as an AMI lookup; AlwaysOn is a real flat
monthly rate, AutoStop prices only the always-billed base fee, not the
additional real per-hour usage charge, a documented floor like Kinesis
Data Analytics/Lambda/SQS/SNS below; the legacy `GRAPHICS` compute type has
no real bundle left in AWS's own price list and stays unpriced;
`aws_workspaces_pool` isn't priced at all: it has no compute-tier
attribute whatsoever, only an opaque `bundle_id`), AWS CodeBuild reserved
capacity fleets (`aws_codebuild_fleet`'s real per-minute rate (always
billed, whether idle or building, since a reserved fleet's machines never
stop), converted to hourly and multiplied by the real declared
`base_capacity`; a genuine 3-way branch: `BUILD_GENERAL1_*` sizes resolve
against `environment_type` for the real OS/architecture family,
`CUSTOM_INSTANCE_TYPE` prices the real declared EC2 `instance_type`
directly, and `ATTRIBUTE_BASED_COMPUTE` replicates AWS's own real
behavior: picking the cheapest of a fixed real menu of shapes whose vCPU
and memory both meet the declared minimums, not just the closest by
vCPU alone), DynamoDB Accelerator
(DAX, priced per node type), AWS Managed
Microsoft AD, Amazon MQ (priced per broker instance type), AWS Backup
(vault storage), CloudHSM, Amazon SageMaker (classic notebook instances;
real-time inference endpoints are priced too, see below), Amazon SageMaker
Studio/RStudio apps (`aws_sagemaker_app`'s real per-instance-type rate for
KernelGateway/CodeEditor/JupyterLab/RStudioServerPro/RSessionGateway,
each a genuinely separate real rate from every other SageMaker compute
type, not the generic notebook/endpoint rate; TensorBoard always runs on
one fixed real instance size regardless of any declared instance_type;
Canvas is priced at a flat real per-session-hour rate, not by instance
type at all; JupyterServer and DetailedProfiler aren't priced: real bulk
data confirms neither has a billable instance rate, JupyterServer only
ever running on an unbilled placeholder value per AWS's own docs), AWS
Elemental MediaConvert reserved queues (`aws_media_convert_queue`'s real
flat monthly rate per Reserved Transcode Slot, times the real declared
`reserved_slots`: the default `ON_DEMAND` pricing plan isn't priced, its
real rate is a large per-minute matrix keyed by codec/resolution/quality/
framerate this tool has no way to pick a single value from statically),
AWS Elemental MediaLive channels (`aws_medialive_channel`'s real input
ingestion rate, keyed by `channel_class` × `input_specification`'s real
codec/resolution/maximum_bitrate, plus one real rate per configured video
output, each output resolved by joining its `video_description_name`
back to the matching `video_descriptions` entry and reading its real
codec_settings, since MediaLive bills inputs and outputs as separate,
independently-metered components, not a single blended channel rate;
H264/H265 are the only two codecs modeled, the only two Terraform's real
schema exposes at all, MPEG-2/AV1 aren't reachable through it; a redundant
`STANDARD` channel_class's cost is already fully baked into its real rate,
not doubled by this tool), AWS
Transfer Family, AWS Direct Connect (dedicated connections, priced per
bandwidth), Amazon ECR (repository storage), Amazon Managed Workflows for
Apache Airflow (MWAA, priced as the sum of an environment's
Environment/Scheduler/WebServer/Worker components), AWS Certificate
Manager Private CA (General-Purpose mode), AWS Certificate Manager public
certificate export (`aws_acm_certificate`'s `options.export = "ENABLED"`:
a real, separate charge AWS introduced in 2026 for exporting a public
certificate's private key, confirmed against the real bulk price list at
$7.00/standard FQDN and $79.00/wildcard domain name; notably different
from the $15/$149 figures circulating secondhand at the time this was
implemented; billed once at issuance and
again at each renewal per AWS's own pricing page, amortized here into a
monthly figure over that ~13-month cycle; counted per distinct FQDN across
`domain_name` + `subject_alternative_names`, standard vs. wildcard rated
separately; correctly $0 for Private-CA-issued certificates, which bill
under ACM Private CA's own SKUs instead), FSx for Lustre/OpenZFS/NetApp
ONTAP (Persistent/Single-AZ SSD baseline rate × each file system's real
declared `storage_capacity`, falling back to a documented assumed-capacity
floor only when that attribute isn't available, e.g. CloudFormation/Pulumi
input or a real restore-from-backup file system), Kinesis Data Analytics v2 (priced at the single-KPU
minimum every application runs at least, same "documented floor" posture as
Lambda/SQS/SNS below), AWS App Runner (priced at an assumed 1 vCPU/2GB
baseline configuration, same reasoning as ECS/Fargate below), Amazon
ECR Public (repository storage), AWS Systems Manager Parameter Store
(Advanced tier), Amazon Timestream for
InfluxDB (priced per DB instance type), Amazon Kendra (index base
capacity fee, Developer or Enterprise edition), Amazon EMR (master node + core instance fleet + task instance
groups (`aws_emr_instance_group`), each node priced
at its EC2 rate plus EMR's own per-instance-hour markup fee; the
instance-fleet configuration API isn't modeled, and a
multi-master HA config's master group is still priced as a single node),
Amazon MemoryDB for Redis/Valkey (priced per node type and engine, since
engine changes the price for the same node type), AWS Managed Blockchain
(peer node instance type, Terraform-only, since this tool's Cloud
Formation/Pulumi support couldn't confidently map a dedicated node
resource for it), Amazon GameLift (fleet EC2 instance type, billed under
GameLift's own service code rather than a markup on EC2 the way EMR's is),
Amazon Neptune Serverless (priced against its real min NCU, cross-referenced
from the owning `aws_neptune_cluster`'s `serverlessv2_scaling_configuration`
for Terraform input, same mechanism and fallback-to-an-assumed-1-NCU-floor
posture as Aurora Serverless v2 above), Amazon MSK Connect (a flat per-MCU-hour rate
times the connector's declared mcu_count x worker_count, only when
configured with fixed/provisioned capacity, not the autoscaling capacity
mode), Amazon DocumentDB Elastic Clusters (a flat per-vCPU-hour rate times
shard_capacity x shard_count; storage/backup aren't modeled), and Amazon
OpenSearch Serverless (an assumed 4 OCU floor: 2 indexing + 2 search,
AWS's own documented minimum for a standard collection, since a
collection has no capacity attribute of its own to read), AWS Database
Migration Service (replication instance type, real Multi-AZ rate — a
genuinely separate SKU, not a multiplier — when the resource's own
`multi_az` is set), EC2 Capacity Reservations (priced at
the same rate as a normal running On-Demand instance of that type — its
real declared `instance_platform`/`tenancy` apply the same OS multiplier/
dedicated-tenancy rate a plain EC2 instance of that type would get, times
instance_count), AWS CodePipeline (a flat $1/month fee per
active pipeline), and Amazon Redshift Serverless (its base_capacity RPU
attribute, a real, already-declared value on the workgroup resource, so
unlike Aurora/Neptune Serverless above this needs no assumed floor at all,
times the real per-RPU rate), and Amazon OpenSearch Ingestion (a
pipeline's min_units, another real declared attribute needing no assumed
floor, times the same per-OCU rate as OpenSearch Serverless above,
confirmed identical across both services), and Amazon AppStream 2.0 (fleet
instance type x compute_capacity.desired_instances), and AWS Storage
Gateway's FSx File Gateway type (`gateway_type = "FILE_FSX_SMB"`), and
Amazon Kinesis Data Streams (real per-shard-hour rate x real declared
`shard_count` for PROVISIONED-mode streams, or a separate real flat
per-stream-hour rate for ON_DEMAND mode, a genuinely different billing
model, not the same rate applied differently; a real declared
`retention_period` above 24h adds the real extended-retention addon for
the 24h-7day band) and Kinesis Stream Consumer/Enhanced Fan-Out
(`aws_kinesis_stream_consumer`, its real shard count resolved from its
`stream_arn` reference to the owning stream), Amazon CloudSearch (real
per-search-instance-type rate), Amazon WorkMail (a flat per-user monthly
fee), Amazon QuickSight users (`aws_quicksight_user`'s real declared
`user_role`: Reader, Reader Pro, and Author Pro each have their own real
flat per-user monthly rate; Author, Admin, Admin Pro, Restricted Author,
and Restricted Reader have no flat rate published by AWS at all and are
left unpriced rather than guessed), AWS Shield Advanced (a flat
account-level monthly subscription fee),
Amazon Athena Capacity Reservations (real per-DPU-hour rate x real
declared `target_dpus`), Amazon FinSpace Managed kdb Kx Clusters (real
per-node-type rate x real declared `node_count`), Amazon Lightsail
Container Service (real per-power-tier rate x real declared `scale`),
AppStream Image Builder (a separate real rate from AppStream Fleet, even
for the identical `instance_type`), and API Gateway stage-level caching
(8 real discrete cache-size tiers, priced on top of the existing
per-request API Gateway rate; $0 when no cache is enabled, the common
case). EC2
Dedicated Hosts are also priced (per instance_family, a whole host is
billed by family, not individual instance size, or, for a host declared via
the mutually exclusive instance_type attribute instead, the same real rate
derived from that attribute's family prefix). Amazon Neptune Analytics
(a graph's provisioned_memory, in NCU, another real, already-declared
attribute needing no assumed floor, times a confirmed-flat $0.03/NCU-hr
rate). AWS MSK Serverless (a flat $0.75/hr per-cluster fee; ingress/egress/
storage/partition usage components aren't modeled). Amazon Q Business
(an index's edition, Starter or Enterprise, times its declared
capacity_configuration.units, another real attribute needing no assumed
floor). AWS Client VPN (a flat $0.10/hr per-endpoint fee; per-connection
usage isn't modeled). Standalone EBS snapshots (`aws_ebs_snapshot`'s
volume_size, a Computed attribute only known post-apply, reuses the
existing snapshot-size pricing this tool already had for RDS backups, no
new pricing wiring needed). AWS Lambda Provisioned Concurrency (an assumed
128MB baseline memory (the real memory_size lives on the
`aws_lambda_function` this config resource references, a cross-reference
this tool's per-resource parsers can't make), times the real
provisioned_concurrent_executions count). Amazon Bedrock Provisioned
Throughput (`aws_bedrock_provisioned_model_throughput`'s model_units (a
real, already-declared attribute needing no assumed floor, same pattern as
Redshift Serverless above), times a per-model-unit-hour rate). model_arn is
resolved against a hand-maintained model-ID lookup table (Terraform/Pulumi
only: no CloudFormation resource for this exists at all), since AWS's price
catalog indexes this by human-readable model name rather than the technical
model ID Terraform/Pulumi expose, and a Provisioned Throughput purchase
requires a context-window-qualified model ID (e.g.
`amazon.nova-lite-v1:0:300k`) that this tool strips back to the base model
before the lookup, since price doesn't vary by context window. Confirmed
region by region against AWS's own published list of
Provisioned-Throughput-eligible models and the real bulk offer file: Amazon's
own Nova/Titan models and Meta Llama 3.1/3.2 have a published rate, each
genuinely region-restricted (Nova/Titan mostly `us-east-1` and a handful of
others, Llama `us-west-2` only, a Llama resource still parses and resolves
its model everywhere, it just only prices in the one region AWS actually
sells it in). Anthropic Claude and Cohere models are purchasable via the
same API but have no corresponding price in AWS's Price List in any region
checked, consistent with those needing a negotiated/quote-only rate rather
than a self-service one, so this tool prices only what AWS actually
publishes. A
`model_arn` pointing at a custom/fine-tuned or imported model isn't resolved
either (`bedrock_provisioned_throughput_unresolved`, same honest-gap posture
as `autoscaling_group_unresolved`): resolving which base model it was
fine-tuned from would need a cross-reference this project deliberately
limits to its four existing cases, `aws_autoscaling_group`/
`aws_sagemaker_endpoint`/Aurora Serverless v2's cluster join/Neptune
Serverless's cluster join, below and above. AWS Glue Jobs
(`aws_glue_job`'s `worker_type` x `number_of_workers`, mapped to AWS's real
per-worker DPU sizing: Standard/G.1X/G.025X/G.2X against the standard
DPU-hour rate, G.4X/G.8X against the memory-optimized rate, Terraform-only,
same posture as Managed Blockchain above).

EC2 Auto Scaling groups (`aws_autoscaling_group`) are also priced: the
first of four resources this tool cross-references another declared
resource for (see `aws_sagemaker_endpoint` below for the second, Aurora
Serverless v2 above for the third, and Amazon Neptune Serverless above for
the fourth). An
ASG's own attributes never carry an instance_type: that lives entirely on
the separate `aws_launch_template`/`aws_launch_configuration` resource it
references (by real, post-apply ID for launch templates; by name for the
older launch configuration), so this parser does a single pre-pass over
every declared resource to resolve that reference before pricing, an
exception to this tool's otherwise strictly single-resource,
no-cross-referencing design (see Amazon Bedrock Provisioned Throughput
below for a case where that design is *not* bent: a `model_arn` pointing
at a custom/fine-tuned model stays unresolved rather than adding a fifth
cross-reference). When `desired_capacity` isn't set, the fleet is priced
at `min_size` — AWS's own documented default for the initial running
count (a refreshed state/plan carries the real running count instead), so
`min_size = 0` prices at $0 until a scaling policy scales it out, and a
`desired_capacity` left unknown by a plan (`null`) is treated the same as
unset rather than as a deliberate scale-to-zero. An
`instance_state` of `stopped`/`stopping` on a plain `aws_instance` drops
its compute (and its released public IPv4) to $0, keeping only its EBS
volumes. An
ASG using `mixed_instances_policy`
(multiple possible instance types with weighted overrides) isn't resolved
from declared config alone: there's no way to know which override
actually gets used without asking AWS directly, so it stays unpriced
(`autoscaling_group_unresolved`) unless `--with-usage` is used (see
[below](#usage-aware-finops---with-usage)) to resolve it from the group's
real, currently-running instances. CloudFormation and Pulumi support this cross-reference too: a CFN
template resolves the join by logical ID (via the `LaunchTemplate.
LaunchTemplateId`/`LaunchConfigurationName` property's `Ref`, since a
static template has no live stack to fetch a real post-apply ID from), and
a Pulumi stack export resolves it by the referenced resource's real,
already-deployed id/name (from its own `Outputs`), same "post-apply ID"
join Terraform's `.tfstate` uses, just read from Pulumi's resource shape
instead.

EKS managed node groups (`aws_eks_node_group`) are priced too, unlike
ASGs, no cross-reference is needed here: `instance_types` and
`scaling_config` are declared directly on the node group resource itself.
Worker nodes are billed as plain EC2 instances (the EKS control plane's own
per-cluster fee is `eks_cluster`'s, fetched separately). Fargate-backed EKS
pods (`aws_eks_fargate_profile`/`AWS::EKS::FargateProfile`/
`aws:eks/fargateProfile:FargateProfile`) are priced too, at an assumed
Fargate baseline (0.25 vCPU/0.5 GB, the smallest Fargate task size, running
continuously), a profile only selects which pods get scheduled onto
Fargate by namespace/label selector; the real per-pod vCPU/memory request
lives in the Kubernetes pod spec, a data source no format this tool parses
exposes. Reuses the exact same fetched rate as ECS/Fargate below (both
services bill the same underlying Fargate compute at the same per-vCPU/
per-GB price), not App Runner's different compute-unit rate. That gap is
closed for a **rendered Kubernetes manifest** input specifically (see
[Input formats](#input-formats) above): a `k8s_workload` resource (a
`Deployment`/`StatefulSet` document, priced from its real declared
`resources.requests`) uses a separate pair of real per-vCPU/per-GB Fargate
rates, not this assumed baseline, the baseline above remains exactly as
accurate as it always was for `aws_eks_fargate_profile` itself (a
Terraform/CloudFormation/Pulumi resource never carries a pod spec), this
is purely additive for the new input format.

`aws_sagemaker_endpoint` (real-time inference) is priced too, the second of
four cross-references this tool's parsers make (see Aurora Serverless v2
and Amazon Neptune Serverless above for the third and fourth): its
`instance_type` lives on a separate
`aws_sagemaker_endpoint_configuration` resource, referenced by name via
`endpoint_config_name`, resolved by the same pre-pass-over-every-resource
pattern `aws_autoscaling_group` uses above. A multi-variant endpoint
configuration (`production_variants` with more than one entry, an A/B
test setup) is priced against its first declared variant only, since this
tool has no way to know real traffic split across variants. CloudFormation
and Pulumi support this cross-reference too, same join as the ASG one
above. Standalone Elastic IPs (`aws_eip`/`AWS::EC2::EIP`/
`aws:ec2/eip:Eip`) are also priced (public IPv4 addresses have billed the
same whether in use or not since Feb 2024, so an EIP resource is priced
identically regardless of association status).

Any other AWS resource type (one this tool hasn't mapped a price for at
all) still shows up in the tree and counts toward the resource total,
priced $0 (indistinguishable from a resource that's genuinely free, like a
security group or a VPC, since neither has a resourceHourly entry to look
up). It never silently disappears from the report the way it used to for
CloudFormation/Pulumi templates before this existed.

Lambda, SQS, SNS, API Gateway, CloudFront(_distribution), GuardDuty,
Security Hub, Config, CloudTrail, and Kinesis Firehose are billed by AWS
purely per-request/GB/event, with no fixed capacity charge Terraform (or
any IaC format) could declare instead: this tool's per-unit rate for
every one of them is always real (freshly fetched from the AWS Price List
API), but the *volume* multiplied against it is a documented default
assumption unless you declare a real one; see
[Real usage volume](#real-usage-volume---usage-file) below. Lambda's
memory size is the one exception that's always real with no extra
step: it's a normal Terraform attribute (`memory_size`), read
automatically.

AWS DataSync (`aws_datasync_task`/`AWS::DataSync::Task`, Basic mode, the
real AWS default) is priced the same per-GB-transferred way, but
deliberately shows **`[Not available]`** rather than a guessed default
volume when no real usage figure is declared: it's a brand-new resource
type with no established "typical monthly transfer" to assume one from,
so a bare number would just be invented. Declare a real `monthly_gb` via
a [--usage file](#real-usage-volume---usage-file) or, on Pro, let
[`--with-usage`](#usage-aware-finops---with-usage) pull the real transferred-bytes
figure from CloudWatch. Enhanced mode isn't priced at all yet (its
separate per-task-execution charge has no usage input modeled).

Amazon Kinesis Video Streams (`aws_kinesis_video_stream`/
`AWS::KinesisVideo::Stream`) gets the same `[Not available]`-until-declared
treatment for its two unambiguous cost components: real per-GB
ingestion (`monthly_gb` in a `--usage` file, or `--with-usage`'s real
CloudWatch `PutMedia.IncomingBytes`) and storage, *derived* from that
ingestion rate × the stream's own declared `data_retention_in_hours`
(always real, no override needed: 0 hours, Terraform's own default,
correctly means $0 storage, matching AWS's real "doesn't persist data"
behavior). Consumption (`GetMedia` and its HLS/DASH/clip variants)
deliberately isn't priced at all: AWS bills it at 4+ different rates
depending on which specific read API an application uses, and nothing in
a declared stream says which one; approximating with any single rate
risked a confidently-wrong number.

Aurora DSQL (`aws_dsql_cluster`/`AWS::DSQL::Cluster`) gets the same
`[Not available]`-until-declared treatment for its real per-DPU compute
cost (`monthly_requests` in a `--usage` file, or `--with-usage`'s real
CloudWatch `TotalDPU`), AWS's single normalized billing unit covering
all query processing, reads, and writes. Storage is priced on top when
available, but **`--with-usage`/Pro only**, no `--usage`-file equivalent:
it's a live snapshot of the cluster's actual current size
(`ClusterStorageSize`), not a monthly volume you could sensibly declare
in advance for a not-yet-existing cluster the way expected traffic can
be.

Kinesis Firehose (`aws_kinesis_firehose_delivery_stream`) got a real
pricing **bug fix**, not just a `--with-usage` addition: a delivery
stream sourced from an existing Kinesis Data Stream
(`kinesis_source_configuration` declared) has no ingestion charge of its
own at all (that data is already billed via the source stream), but
this tool previously charged it the same flat assumed-volume heuristic
as every other Firehose stream. It now correctly prices at $0. A
Direct-PUT-sourced stream (the default, no source block declared) keeps
its existing heuristic and additionally gets real `--with-usage`
refinement from CloudWatch's `IncomingBytes`. MSK-sourced streams
(`msk_source_configuration`) aren't distinguished from Direct-PUT yet:
a real, separate AWS rate, left as a known gap rather than approximated.

SQS (`aws_sqs_queue`) also gets real `--with-usage` refinement, from
CloudWatch's real `NumberOfMessagesSent`, with one honestly-documented
imprecision: AWS bills SQS per API *request*, not per message, so a
`SendMessageBatch` call carrying 10 messages is 1 billable request but
shows as 10 in this metric. For applications that send/receive one
message at a time (no batching), the number is exactly correct; for
batching applications it overstates the real cost. Still a real,
measured number, not an invented one, just an imperfect proxy for the
literal billing unit in that one case.

CloudFront (`aws_cloudfront_distribution`) gets real `--with-usage`
refinement too, from CloudWatch's real `BytesDownloaded`. This one needs
extra plumbing under the hood most `--with-usage` types don't: CloudFront
is a global service, so its CloudWatch metrics only ever exist in the
`us-east-1` region's CloudWatch API (regardless of the infrastructure's
own pricing region), and every CloudFront metric needs a fixed
`Region=Global` dimension alongside `DistributionId`, both handled
automatically. The existing per-GB data-transfer-out rate this refines
covers `BytesDownloaded` only, matching the flat heuristic it replaces:
`Requests` and CloudFront's real edge-location price-class tiering
aren't modeled.

SNS (`aws_sns_topic`) gets real `--with-usage` refinement from
CloudWatch's real `NumberOfMessagesPublished`, dimensioned by the topic's
real declared `name` (Terraform's own `id` for this resource is the
topic's ARN, not a CloudWatch-compatible dimension value). This only
refines the publish side, matching what the existing flat heuristic
already assumed: SNS's real cost is usually dominated by per-protocol
delivery fanout (SMS/push/HTTP/email/SQS/Lambda), each billed at a very
different rate, which isn't measured or priced by this tool at all.

GuardDuty (`aws_guardduty_detector`) gets real `--with-usage` refinement
from CloudWatch's real `AnalyzedCount`. Unlike every other `--with-usage`
type, GuardDuty allows only one detector per account per region, so its
metrics carry no per-detector dimension at all: AWS scopes them by the
account's real `AccountId` (a computed attribute this tool reads directly
off the detector resource) plus a fixed `DataSource=CloudTrailEvents`
dimension instead. This only refines the CloudTrail-events component,
matching the existing flat heuristic's own scope: `AnalyzedBytes` (VPC
Flow Logs/DNS logs, the other Foundational Threat Detection component,
often the larger one) and every other protection plan (S3, EKS, Malware,
Runtime Monitoring, RDS, Lambda, AI) aren't priced by this tool at all
yet. CloudFormation input can't resolve `AccountId` at all (no such
property exists on `AWS::GuardDuty::Detector`, it's implicit to the
stack's deploy target, not something a static template declares), so this
refinement only activates for Terraform/Pulumi input.

DynamoDB (`aws_dynamodb_table`) on-demand tables get a real, exact price
from `--with-usage`'s live CloudWatch `ConsumedReadCapacityUnits`/
`ConsumedWriteCapacityUnits` (or `monthly_dynamo_read_request_units`/
`monthly_dynamo_write_request_units` in a `--usage` file), multiplied by
AWS's real per-Read/Write-Request-Unit rate — not an estimate, the same
metric names DynamoDB publishes under either billing mode, since
on-demand's Request Units are defined identically to provisioned RCU/WCU
consumption. Without either, an on-demand table still prices from the same
flat assumed-baseline heuristic it always has (never a bare $0). This also
fixed a real, unrelated bug found along the way: a *provisioned* table with
real declared `dynamo_rcu`/`dynamo_wcu` was getting that same flat baseline
added **on top of** its real capacity cost — a confirmed double-charge,
now gone regardless of `--with-usage`.

Amazon Managed Service for Prometheus' fully-managed collector
(`aws_prometheus_scraper`/`AWS::APS::Scraper`) is priced at its real flat
per-hour rate: a single "managed collector" charge with no capacity
attribute to size against. The workspace it scrapes into
(`aws_prometheus_workspace`) is deliberately left unpriced rather than
approximated: it has no capacity attribute either, and none of its 3 real
billing components (ingestion, storage, query processing) has a
CloudWatch metric with a per-workspace dimension (confirmed against
AWS's own CloudWatch metrics reference, not just unresearched), so the
real tiered billing can't be measured or declared for a single workspace,
only guessed, and this tool doesn't guess.

AWS M2/Mainframe Modernization (`aws_m2_environment`/
`AWS::M2::Environment`) is priced by each environment's real declared
`instance_type` × `engine_type` (Enterprise Server/Micro Focus and Blu Age
Runtime are genuinely priced ~18x apart per vCPU, not a typo), multiplied
by `high_availability_config.desired_capacity`'s real declared instance
count, defaulting to 1 the same way a real M2 environment with no HA
config does. The externally-provisioned EFS/FSx storage an environment can
attach isn't priced here; that capacity belongs to those resources' own
separate AWS charge, not M2's. Note this is a service AWS closed to new
customers on 2025-11-07; still fully priced for existing customers'
infrastructure, whose bulk rates remain live.

EKS Capabilities (`aws_eks_capability`, AWS's managed ACK/KRO/ArgoCD
add-ons) are priced by real declared `type`, each at its own real flat
per-capability-hour rate, nested under the owning `aws_eks_cluster` via
`cluster_name`. EKS Extended Support is priced as a real flat
per-cluster-hour surcharge, added only when `upgrade_policy.support_type`
is explicitly declared `"EXTENDED"` — a cluster AWS auto-enrolled into
extended support without the Terraform config reflecting it stays
under-counted, a documented limitation rather than an inferred guess from
Kubernetes version/EOL dates. Lambda SnapStart's Cached tier is priced as a
real, continuous GB-second surcharge (the same billing shape as Provisioned
Concurrency) using the function's own real `memory_size`, when
`snap_start.apply_on = "PublishedVersions"` is declared; the separate
per-cold-start Restored-GB charge needs real invocation/restore-count data
this tool has no static source for, so it's deliberately left unpriced.
DynamoDB Streams' real per-read-request-unit rate (beyond AWS's real
2.5M-request/month free tier) is priced from a declared `stream_enabled`
table plus a `--usage` file's `monthly_stream_read_request_units`.
CloudFront Origin Shield's real per-request rate is priced the same way,
from a declared `origin_shield.enabled` distribution plus
`monthly_origin_shield_requests`. S3 Replication Time Control's real,
region-pair-independent $/GB surcharge is priced from a declared
`aws_s3_bucket_replication_configuration` (nested under its source bucket)
whose `destination.replication_time.status` is `"Enabled"`, plus a
`--usage` file's `monthly_replicated_gb` — plain (non-RTC) cross-region
replication data transfer stays unpriced, since its real rate genuinely
depends on the destination bucket's region, which this tool doesn't
resolve. GuardDuty Protection Plans (`aws_guardduty_detector_feature`) and
EKS Auto Mode (`compute_config.enabled`) are both surfaced as $0
informational findings, never a dollar figure — their real usage (vCPU-
hours monitored, GB scanned, dynamically-provisioned EC2 Managed
Instances) has no static Terraform attribute or bulk-API-derivable volume
this tool can price from.

## FinOps recommendations

Every dollar figure is computed by re-pricing the actual resource against
the same price catalog used for the cost tree, never a flat guessed
percentage. Rules run against *declared* configuration by default (no
telemetry needed, no AWS account needed):

- **gp2 → gp3** (EBS and RDS/RDS Cluster storage): gp3 is cheaper per GB
  and already bundles 3000 IOPS / 125MB/s throughput.
- **Provisioned IOPS (io1/io2) → gp3**: when provisioned IOPS are at or
  below gp3's bundled baseline.
- **Previous-generation instance type** (t2→t3, m4→m5, c4→c5, r4→r5,
  m3/c3/r3→…5): same size class, cheaper and faster, across EC2/RDS/
  ElastiCache.
- **x86 → Graviton (ARM64)** (t3→t4g, m5→m6g, c5→c6g, r5→r6g, EC2/RDS):
  cheaper at the same size, but unlike every other repricing rule above
  this changes CPU architecture, so the message always asks you to confirm
  ARM64 compatibility (AMI/container base image, compiled dependencies)
  first; it's never framed as a free win. Quantified with a real $/mo
  figure on **Pro** when the catalog has a matching rate for that specific
  size (Graviton coverage in the published catalog is narrower than x86's:
  a size with no matching rate is silently skipped, same as any other
  repricing rule); Free sees an unquantified ~20-40% nudge instead. Not yet
  applied to ElastiCache: real-per-node-type pricing landed, but this
  rule's family-swap logic still needs a follow-up to parse ElastiCache's
  composed `<node_type>_<engine>` instance-type format.
- **RDS Multi-AZ**: flags the doubled compute cost, asking you to confirm
  HA is genuinely needed.
- **RDS backup retention above 30 days**: re-priced at the 30-day cap.
- **NAT Gateway, low traffic**: compares the fixed hourly rate against a
  `t3.micro` NAT instance when monthly data processed is under 15GB.
- **DynamoDB provisioned, high capacity**: suggests on-demand when combined
  RCU+WCU is high. This tool doesn't model on-demand's real per-request rate
  yet, so the comparison is against a flat assumed-low-capacity baseline, not
  your table's real traffic — a busy table running near its provisioned
  RCU/WCU can genuinely cost *more* on-demand, so confirm your real
  utilization before switching. Never auto-applied by `--optimize` for
  exactly this reason.
- **EC2 fleet without an Auto Scaling Group**: a `count > 1` resource with
  no ASG settings; informational (elasticity, not a quantified saving).
- **Reserved Instance / Savings Plan candidate**: steady-state (no
  autoscaling, default 24/7 hours), high-cost EC2/RDS. Quantified with a
  real $/mo figure on **Pro** when the catalog has a matching Reserved
  rate; Free/no-catalog-match sees the unquantified nudge. See
  [below](#real-reserved-instance-savings).
- **Non-production resource running 24/7**: an EC2/RDS/RDS Cluster
  resource tagged or named as dev/staging/test/qa/sandbox (an `Environment`-
  style tag, or a whole `-`/`_`/`.`-separated token of its name, not a raw
  substring match, so `latest-app` or `underdevelopment-svc` don't
  false-positive) with no autoscaling and still priced at the full default
  24/7 hours. Re-priced exactly at an assumed business-hours-only schedule
  (~173h/month, 40hr/week) via the same `HoursPerMonth` math
  `--hours-per-month` already uses, so the savings figure is real, not a
  flat percentage guess, available on **every plan**, since unlike the
  Reserved/Graviton rules above it needs no new pricing data asset, just
  logic over what's already declared. A resource that already has a reduced
  `HoursPerMonth` set (already scheduled) is never re-flagged.
- **Governance nudges** (no dollar figure): missing tags/generic resource
  names, Terraform's implicit `default_*` resources (default security
  group, VPC, route table, network ACL) left unmanaged, and an S3 bucket
  with no lifecycle/storage-class transition rule declared (checked both
  ways the AWS provider expresses one: the modern, separate
  `aws_s3_bucket_lifecycle_configuration` resource, or the older
  deprecated `lifecycle_rule` block on `aws_s3_bucket` itself, no dollar
  figure, since this tool has no way to know a bucket's real object
  count/size/access pattern). Shown standalone only when there's no real
  cost saving elsewhere (condensed, one line per issue), or always
  alongside cost recommendations with `--include-governance`.

Only shown when `--with-usage` (**Pro**) actually fetched real telemetry;
never a guess: **real CPU-based right-sizing**, **live Spot pricing**,
**confirmed orphaned EBS volumes/snapshots**, **confirmed empty-target-group
load balancers**, **confirmed unassociated Elastic IPs**, and **real
Lambda memory right-sizing**; see [below](#usage-aware-finops---with-usage).

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

Available on **every plan**: no AWS account needed. Lambda, SQS, SNS, API
Gateway, CloudFront(_distribution), GuardDuty, Security Hub, Config,
CloudTrail, and Kinesis Firehose are billed by AWS purely per-request/GB/
event; nothing in a Terraform/CloudFormation/Pulumi declaration says how
much traffic one of them will actually get, so by default this tool prices
them against a documented, conservative assumption (1,000,000 requests/
month, etc.). A `--usage` file lets you declare the real number you
actually expect, keyed by the resource's Terraform address:

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
  aws_lb.web:
    avg_lcus: 25
```

ALB/NLB/GWLB are a different shape from the purely usage-based types above:
AWS bills them a flat per-hour attachment fee *plus* a real, separate
per-LCU-hour charge (Load Balancer Capacity Units — driven by connections,
bandwidth, and for ALB rule evaluations) that Terraform/CloudFormation/
Pulumi can't know ahead of time either. `avg_lcus` declares your real
average consumed LCUs; with no entry, only the flat attachment fee is
priced, exactly as before this field existed.

No file, or no entry for a given resource, changes nothing: the
documented assumed volume applies exactly as it always has, so this is
purely additive. Lambda's `memory_size` is priced for real regardless of
whether you use this file at all (Terraform already declares it); a
`--usage` entry additionally lets you correct the invocation count and
average duration, the two inputs Terraform genuinely can't know. Run
`cloudcosttree <file>` without `--usage` and CloudCostTree tells you
directly, on that same run, when a shown figure still rests on the
assumed default rather than a real number: the disclosure lives next to
the number itself, not just in this README.

On **Pro**, `--with-usage` (below) goes one step further for Lambda,
DataSync, API Gateway, Kinesis Video Streams, Aurora DSQL, Direct-PUT
Kinesis Firehose, SQS, CloudFront, SNS, GuardDuty, and on-demand DynamoDB
tables specifically: it replaces even a
`--usage` file's declared volume with what a *real, already-deployed*
resource's CloudWatch metrics show it actually did; see the
[Usage-aware FinOps](#usage-aware-finops---with-usage) section below for
exactly which real metric each one uses.

## Custom price books

```
cloudcosttree ./my-infra.tf --price-overrides discounts.yaml
```

Available on **every plan**: no AWS account, no hosted service. If your
org has a negotiated/EDP discount with AWS, declare a flat percentage off
per resource type (`service`, the same string as a policy's
`resource_type`, e.g. `ec2`/`rds`/`ebs`), optionally scoped to one region:

```yaml
version: "1.0"
overrides:
  - service: ec2
    discount_percent: 10
  - service: rds
    region: us-east-1
    discount_percent: 15
```

A region-specific entry wins over a region-omitted (every-region) one for
the same service, regardless of file order. No file, or no entry for a
given resource's type, changes nothing: the catalog's real on-demand rate
applies exactly as it always has.

This is deliberately an MVP: a flat percentage per service, not a model of
how a real EDP's discount can vary by purchase type (on-demand vs.
Reserved Instance vs. Savings Plan), every discounted figure still starts
from a real, fetched AWS rate, this is just a multiplier applied on top of
it.

## Real Reserved Instance savings

`ruleReservedCapacityCandidate`'s "this looks like a Savings Plan / Reserved
Instance candidate" nudge is quantified with a real dollar figure whenever
the price catalog has a 1-year, no-upfront Reserved Instance rate for the
resource's EC2 instance type or RDS instance class (refreshed by the same
`update-prices`/`generate-prices` pipeline as on-demand rates, no extra AWS
account or credentials needed to see it, since the rate ships in the
public, published catalog).

**Savings Plans** are no longer just a nudge under `--with-usage` (Pro): the
tool reads your account's active plans (`savingsplans:DescribeSavingsPlans`)
and their real discounted per-usage-type rates
(`savingsplans:DescribeSavingsPlanRates` — AWS's own numbers, not inferred),
matches them (plus held EC2/RDS Reserved Instances, Reserved Cache Nodes,
Reserved Redshift Nodes, and Reserved OpenSearch Instances) against your
steady-state EC2 / RDS / ElastiCache / Redshift / OpenSearch capacity, and
prints a **commitment coverage**
section: list price, your effective rate, and what the commitment saves, as
separate figures. See [Usage-aware FinOps](#usage-aware-finops---with-usage).

This is a **CloudCostTree Pro** feature: Free always sees the original,
unquantified nudge, even when the catalog does have a matching rate.

## Usage-aware FinOps (`--with-usage`)

```
cloudcosttree analyze ./my-infra.tf --with-usage
```

A **CloudCostTree Pro**, opt-in flag that calls your own read-only AWS
credentials (the default credential chain: env vars, a shared profile, SSO,
or an EC2/ECS/Lambda instance role, independent of any `profile` argument
on the input `.tf` file's own `provider "aws"` block, which only Terraform
itself reads; export `AWS_PROFILE=<name>` to point this flag at a named
profile) to replace static-config guesses with
real numbers (and confirm facts no static config can know at all, like an
EBS volume's real attachment status), for resources this tool can resolve a
real AWS resource ID for: a `.tfstate` file, a `terraform show -json` plan
against already-applied infrastructure, a `pulumi stack export`'s
per-resource `outputs.id`/`outputs.arn`, or a CloudFormation template paired
with `--stack-name <name>` (below). A brand-new resource being `create`d for
the first time (Terraform), or one Pulumi hasn't deployed yet (empty
`outputs`), has no real ID and is silently skipped for this enrichment (the
rest of the report is unaffected).

CloudFormation input is the one format that can't carry a real resource ID
itself at parse time: a plain template has no post-apply state of its own,
unlike the two deployment-aware formats above, so it needs one extra
opt-in step: `--stack-name <name>`, the name of the stack this template was
actually deployed as (`aws cloudformation create-stack --stack-name <name>
...`). With it, `--with-usage` makes one extra, read-only
`cloudformation:DescribeStackResources` call to resolve every resource's
real physical ID from its logical ID (matched the same way this tool's own
CloudFormation parser already keys resources by logical ID, see
`pkg/parser/cloudformation.go`), then every enrichment below runs exactly as
it would for a Terraform/Pulumi resource with a real ID. Without
`--stack-name`, CloudFormation input is skipped for `--with-usage` exactly
as before (a printed note, never a failure).

- **Real CPU-based right-sizing**: pulls each EC2/RDS/RDS Cluster
  resource's actual average CPU utilization from CloudWatch
  (`CPUUtilization`, 14-day lookback) and, when it's genuinely idle
  (under 10% average), recommends one size down within the same instance
  family/generation (e.g. `m5.xlarge` → `m5.large`) with an exact repriced
  dollar delta, instead of guessing anything from the declared instance
  type alone. Reserved-Instance-aware: also calls
  `ec2:DescribeReservedInstances` for every distinct EC2 instance type in
  your infrastructure, and when the account holds one or more active RIs of
  that exact type, the recommendation is caveated rather than silently
  suppressed: an RI existing doesn't confirm *this specific* instance is
  the one it covers (an account can run more instances of a type than it
  holds RIs for), so this tool never guesses either way. Stranding a paid
  RI commitment while paying on-demand for a smaller instance is often
  net-negative, which is exactly what the caveat asks you to check first.
- **Live EC2 Spot pricing**: pulls the current Spot price
  (`ec2:DescribeSpotPriceHistory`, Linux/UNIX) for every distinct EC2
  instance type in your infrastructure and quotes the real
  on-demand-vs-Spot delta. Interruption risk is always called out in the
  message (Spot capacity can be reclaimed with two minutes' notice), this
  tool has no way to know if your workload tolerates that, so it never
  hides the tradeoff.
- **Real usage-based cost correction** (Lambda, DataSync, API Gateway,
  Kinesis Video Streams, Aurora DSQL, Kinesis Firehose, SQS, CloudFront):
  unlike the two recommendations above, this corrects the cost tree's
  own headline number, not just a FinOps suggestion alongside it. Each
  type gets its own real CloudWatch metric in place of a `--usage`
  file's declared volume or the assumed default: the same
  real-vs-guessed gap [above](#real-usage-volume---usage-file), just
  backed by measurement: Lambda's `Invocations`/`Duration`; DataSync's
  (Basic mode) and Kinesis Video Streams' `BytesTransferred`/
  `PutMedia.IncomingBytes` (neither has an assumed-default fallback at
  all, so this is what turns a `[Not available]` into a real number, not
  just a correction to an already-real one); API Gateway's `Count` (AWS
  scopes this differently between REST and HTTP APIs, by the declared
  `name` vs. the `id`, which this tool resolves automatically); Aurora
  DSQL's `TotalDPU` plus, additively, its live `ClusterStorageSize` (the
  one input on this whole list with no `--usage`-file counterpart, since
  a live snapshot size can't be meaningfully pre-declared); Kinesis
  Firehose's `IncomingBytes` (Direct-PUT-sourced streams only: a
  KDS-sourced stream is already a hard $0, see above, not a volume guess
  to refine); SQS's real `NumberOfMessagesSent` (with one documented
  imprecision: AWS bills per API request, not per message, so a batching
  application's real cost is understated by this metric; see above);
  and CloudFront's real `BytesDownloaded` (its CloudWatch metrics only
  exist in `us-east-1` regardless of the infrastructure's own pricing
  region, handled automatically, not something you need to configure).
  EC2/RDS CloudWatch data stays recommendation-only, deliberately: an
  EC2 instance's on-demand rate is already a hard catalog fact, not a
  volume guess the way every type in this list's declared cost is.
- **Confidence range on usage-priced estimates**: every metric above is
  pulled as a real daily time series over the lookback window (not one
  window-wide average), so this tool can measure actual day-to-day
  variance instead of just a mean. When that variance is meaningful, the
  affected resource's `--export json` entry carries
  `monthly_range_low_usd`/`monthly_range_high_usd` alongside its single
  `monthly_usd` figure — a real measured spread, never an invented
  ±X% band, and the console run prints a one-line note pointing you at
  it. A `--usage` file value or the documented assumed default never
  gets a range (there's no measurement behind a number you typed by
  hand or a flat industry default) — only `--with-usage`'s real
  CloudWatch data does. [`history compare`'s "usage" cause
  attribution](#cost-delta-attribution) also uses this same measured
  variance, when both compared snapshots have it, instead of a flat
  percentage cutoff, to tell a genuine consumption change apart from
  ordinary day-to-day noise.
- **Real `mixed_instances_policy` resolution**: another headline-number
  correction, not just a recommendation. An Auto Scaling Group using
  `mixed_instances_policy` has no single declared `instance_type` at all
  (multiple possible overrides, weighted): declared config alone can't
  say which one actually got launched, so it renders unpriced
  (`autoscaling_group_unresolved`) without this. Calls
  `autoscaling:DescribeAutoScalingGroups` for every such ASG this tool can
  resolve a real ASG name for, which already reports each running
  instance's real `InstanceType` directly (no separate
  `ec2:DescribeInstances` call needed), and prices the group as the most
  common instance type among its currently `InService` instances, a
  mixed group can genuinely run more than one type at once, and this tool
  prices a resource as a single type × count, not a weighted mix.
- **Confirmed orphaned EBS volumes**: calls `ec2:DescribeVolumes` for every
  standalone EBS volume this tool can resolve a real volume ID for and flags
  the ones AWS confirms are genuinely unattached (`State: available`), at
  their full monthly cost. Deliberately not a static rule: a config-only
  check ("nothing in this file references this volume") would flag volumes
  that are actually attached via a separate Terraform root/module this tool
  never parsed, a false accusation this project's FinOps rules never make.
- **Confirmed orphaned EBS snapshots**: calls `ec2:DescribeSnapshots` for
  every standalone snapshot this tool can resolve a real snapshot ID for,
  then `ec2:DescribeVolumes` to confirm its source volume no longer
  exists, at the snapshot's full monthly cost. Same "AWS's own ground
  truth, not a config-only guess" discipline as the orphaned-volume check
  above.
- **Confirmed empty-target-group load balancers**: calls
  `elasticloadbalancing:DescribeTargetGroups` + `DescribeTargetHealth`
  for every ALB/NLB/GWLB this tool can resolve a real ARN for, and flags
  the ones with zero registered targets across every target group behind
  them, at the load balancer's full monthly cost. Classic ELB isn't
  covered (it predates ELBv2's target-group model entirely).
- **Confirmed unassociated Elastic IPs**: calls `ec2:DescribeAddresses`
  for every standalone EIP this tool can resolve a real allocation ID
  for, and flags the ones confirmed unassociated, at the address's full
  monthly cost, AWS bills a public IPv4 address the same whether it's
  attached to anything or not (since Feb 2024), so an unassociated one is
  pure waste, not "used to be free."
- **Orphaned-on-destroy warnings**: when the input is a live Terraform
  plan that destroys an EC2 instance, calls `ec2:DescribeVolumes`/
  `DescribeAddresses` (filtered by the doomed instance's real ID, a
  discovery scan, not an ID lookup, since a dependent left outside this
  Terraform config was never going to have a resource ID this tool already
  knows) to check for an EBS volume/Elastic IP that's genuinely still
  attached/associated to it right now, and isn't itself being destroyed in
  the same plan. Unlike the confirmed-orphan checks above (which catch a
  dependent *already* unattached), this is a preview: the dependent is
  still in use today, but `apply`-ing this exact plan would silently leave
  it behind, unattached, still billing, caught before that happens instead
  of on the next `--with-usage` run after the fact. Needs no new IAM
  permission beyond `ec2:DescribeVolumes`/`DescribeAddresses`, already
  required above. `.tfstate`, CloudFormation, Pulumi, and this tool's own
  YAML/JSON schema have no "pending change" concept at all (they describe
  what exists, not what a plan is about to do), so this check only ever
  runs for a live Terraform plan.
- **Lambda memory over-provisioning**: CloudWatch Metrics has no
  `MemoryUtilization` metric for Lambda at all (unlike EC2/RDS
  `CPUUtilization`), so this queries CloudWatch Logs Insights
  (`logs:StartQuery`/`GetQueryResults`) against every function's own
  `/aws/lambda/<name>` log group for the real average max-memory-used AWS
  writes to every invocation's `REPORT` log line, genuinely measured, not
  a metric this tool had to approximate. When that average sits well under
  the function's currently configured `memory_size`, recommends a smaller
  value (with headroom above what was actually measured) at an exact
  repriced dollar delta, disclosing the one real tradeoff it can't
  quantify: Lambda's CPU allocation scales with `memory_size`, so Duration
  should be re-checked after lowering it.
- **Fleet size outlier**: compares a plan's EC2/RDS resource against every
  other instance already running in that same AWS account/region
  (`ec2:DescribeInstances`/`rds:DescribeDBInstances`, grouped by instance
  family the same way `ruleOldGenerationInstance`/`ruleGravitonMigration`
  parse one), and flags it only when it's a genuine outlier against a real
  sample of at least 2 comparable instances: a different family than
  whichever one is most common in the fleet, or the largest size within a
  family it does share. No dollar figure: this tool has no way to know
  whether the new resource's size is a genuine business need, so it's a
  governance/consistency nudge, not a quantified saving, the same
  informational posture as `ruleEC2FleetWithoutASG`. Silent whenever there's
  no comparable fleet at all, or fewer than 2 other instances to compare
  against, this never guesses from a tiny sample. EC2 and RDS only for
  now; RDS Cluster/Aurora and ElastiCache aren't in scope yet.
- **Reserved coverage gap**: calls `ec2:DescribeReservedInstances`,
  `rds:DescribeReservedDBInstances`, `elasticache:DescribeReservedCacheNodes`,
  `redshift:DescribeReservedNodes` and `es:DescribeReservedInstances` (all
  already required above/free, unlike a hypothetical future Savings-Plans
  version of this check, which would need AWS Cost Explorer's API, billed
  per call; this one adds no AWS bill of its own) and compares real held
  reservation counts against every steady-state (no autoscaling, default
  24/7 hours, the same gate `ruleReservedCapacityCandidate` uses) EC2 / RDS /
  ElastiCache / Redshift / OpenSearch instance type / node type / class
  actually declared here. When declared count exceeds held count, flags the
  uncovered gap with a real repriced dollar figure: what buying enough more
  1-year no-upfront reservations to cover the rest would save. Unlike
  `ruleReservedCapacityCandidate` above (which only ever asks "would an RI
  help, hypothetically," blind to what the account already owns), this is
  the account's real inventory, so a team that's already fully RI-covered
  for a given type sees nothing here instead of a repeated nudge. Inherits
  one blind spot from the underlying fetch: an RI's OS/product-description
  and region-vs-availability-zone scope aren't captured, so a Windows RI
  and a Linux RI of the same instance type (or an AZ-pinned RI) are folded
  together as undifferentiated coverage for that type, a real, disclosed
  approximation, not a guess invented by this check.
- **NAT Gateway → Gateway VPC endpoint**: when a NAT Gateway processed a
  meaningful amount of data (measured, above 100 GB/month) and the
  infrastructure also has S3 and/or DynamoDB resources, flags that traffic to
  those two can go through a **Gateway VPC endpoint** — which AWS doesn't
  charge for — instead of the NAT Gateway's per-GB data-processing rate. An
  informational ($0) nudge, not a quantified saving: CloudWatch's NAT metrics
  don't split processed bytes by destination, so the eliminable S3/DynamoDB
  share can't be measured without VPC Flow Logs. The message states the full
  measured processing charge as the ceiling and is explicit that the real
  amount is a fraction of it. The offered what-if models the best case (all
  NAT processing gone) and is never auto-applied by `--optimize`.

### Multi-region and multi-account (`--accounts`)

Every call above is made once per distinct AWS region actually declared
across the infrastructure's resources (each resource's own `region` falling
back to the top-level one when unset), not just once for the whole run,
so a Terraform config spanning several regions gets real data for every
resource, not just whichever region happened to be checked first.

For an infrastructure whose resources span more than one AWS **account**
(e.g. several `provider` aliases, each assuming a different role), an
optional `accounts.yaml` maps a resource address/name pattern to the
`role_arn` that resource's calls should assume:

```yaml
version: "1.0"
accounts:
  - match: "module.prod.*"
    role_arn: "arn:aws:iam::111111111111:role/cloudcosttree-readonly"
  - match: "module.staging.*"
    role_arn: "arn:aws:iam::222222222222:role/cloudcosttree-readonly"
```

`--accounts <path>` points at it explicitly; without the flag, this tool
looks for `./accounts.yaml`, then `~/.cloudcosttree/accounts.yaml`, same
convention as `--policies`. `match` is matched against a Terraform
resource's own address when it has one (`module.prod.aws_instance.web`),
falling back to its plain name for every other input format. A resource
matching no entry (or when no `accounts.yaml` exists at all) uses the
default AWS credential chain, exactly as `--with-usage` always did; this is
purely additive. Needs `sts:AssumeRole` on the credentials running
`--with-usage`, plus a trust policy on each target `role_arn` allowing that
principal to assume it.

Needs `cloudwatch:GetMetricData`, `ec2:DescribeSpotPriceHistory`,
`ec2:DescribeVolumes`, `ec2:DescribeSnapshots`, `ec2:DescribeAddresses`,
`ec2:DescribeReservedInstances`, `ec2:DescribeInstances`,
`rds:DescribeDBInstances`, `rds:DescribeReservedDBInstances`,
`savingsplans:DescribeSavingsPlans`, `savingsplans:DescribeSavingsPlanRates`,
`elasticache:DescribeReservedCacheNodes`, `redshift:DescribeReservedNodes`,
`es:DescribeReservedInstances`,
`elasticloadbalancing:DescribeTargetGroups`/`DescribeTargetHealth`,
`logs:StartQuery`/`logs:GetQueryResults`,
`autoscaling:DescribeAutoScalingGroups`, and (with `--stack-name`,
CloudFormation input only) `cloudformation:DescribeStackResources` IAM
permissions. The `savingsplans:*` and `*DescribeReserved*` calls are all
free description calls (no Cost Explorer, no per-request billing); they feed
the **commitment coverage** section, which prints list price next to what
your held Savings Plans / Reserved Instances / Reserved Cache Nodes /
Reserved Redshift Nodes / Reserved OpenSearch Instances actually bill you —
as separate figures, never blended into the headline total. It also shows a
**whole-stack effective total**: the tree's list total minus only the real
commitment savings (covered EC2/RDS at their effective rate, everything else
still at list — labelled as such, not presented as a full effective bill).
A right-sizing recommendation for a covered instance also carries a
stranded-commitment
caveat.

`--with-usage` also measures **data transfer** for NAT Gateways and Transit
Gateways from the CloudWatch byte metrics AWS already publishes — data
processing plus NAT internet egress, priced against the real per-GB rate
cards, needing no extra permission beyond `cloudwatch:GetMetricData`.
NAT internet egress is priced against AWS's full tiered rate ladder (first
10 TB/month, then the $0.085 / $0.07 / $0.05 bands). Cross-AZ / inter-AZ
transfer, direct-to-IGW instance egress and inter-region egress are measured
separately with [`--flow-logs`](#measured-data-transfer---flow-logs) below.
`ec2:DescribeInstances`/`rds:DescribeDBInstances` are the one
pair above that scan the whole account/region rather than looking up
specific resources by ID (every other call here targets IDs this tool
already resolved), that's what the fleet size outlier check above needs to
see what else is already running. A
missing-credentials or missing-permission problem is
reported with an actionable message (not a raw SDK stack trace) and never
fails the run, the rest of the report still renders normally without the
extra recommendations. On Free, `--with-usage` is accepted but ignored
(prints a one-line upgrade note; the rest of the run is completely
unaffected). Deliberately **not** available during a `--<flag>` what-if
simulation: real CloudWatch data belongs to the resource as it exists
today, not to a hypothetically-resized simulated version of it.

### Confidence range on the total

Usage-priced resources (Lambda, SQS, SNS, DynamoDB on-demand, NAT/Transit
Gateway data transfer, …) carry real day-to-day variance, measured as the
standard deviation of their own daily CloudWatch datapoints over the
lookback window. Under `--with-usage`, those per-resource spreads are
combined — as independent variances (√Σσ²), not a linear sum — into a
single range shown under the headline:

```
Current Total: $509.23/month
  Range:       $480.12 – $540.44/month   (±1σ measured usage variance, --with-usage)
```

Resources with no variance signal (a `--usage` file value, the assumed
default, a fixed hourly rate) enter the total as a point and widen nothing.
The range only appears when there is real measurement behind it — it is
never a fabricated ±X% band. Per-resource spreads are in `--export json`
(`monthly_range_low_usd` / `monthly_range_high_usd`); the combined total is
`total_monthly_range_low_usd` / `_high_usd`.

### Measured data transfer (`--flow-logs`)

```
cloudcosttree analyze ./my-infra.tf --flow-logs
```

`--flow-logs` (**Pro**, implies `--with-usage`) prices the data-transfer
dimensions CloudWatch metrics can't isolate, from your infrastructure's
**existing** VPC Flow Logs (CloudWatch Logs destination) read via CloudWatch
Logs Insights:

- **Cross-AZ / inter-AZ transfer inside a region** ($0.01/GB each direction).
  Each flow's endpoints are mapped to their ENI's Availability Zone and the
  bytes that cross an AZ boundary are summed. Because AWS logs an intra-VPC
  flow from both ENIs, summing every matching record reproduces AWS's
  bill-both-directions model with no doubling assumption.
- **Direct-to-internet egress via an Internet Gateway** — a public-subnet
  instance with a public IP reaching the internet without a NAT hop. Priced
  against AWS's full tiered egress rate ladder, billed one direction only.
  Egress **through a NAT Gateway** is already measured from CloudWatch
  (`BytesOutToDestination`) and is explicitly excluded here, so nothing is
  double-counted. Load-balancer egress to internet clients is not included.
- **Inter-region egress** — a flow to a public IP that AWS's `ip-ranges.json`
  places in another region, priced per destination region (`InterRegion
  Outbound` rates vary by pair — e.g. $0.02/GB from us-east-1 to most regions,
  $0.01 to us-east-2). A destination pair the catalog has no rate for is
  disclosed, not guessed. Inter-region traffic over VPC peering / Transit
  Gateway / PrivateLink uses private addresses and is not visible to Flow
  Logs — disclosed too.

Public destinations are classified using AWS's public `ip-ranges.json`,
fetched once and cached ~7 days under `~/.cloudcosttree/`.

It **never enables Flow Logs** — that's a change to your infrastructure with
its own ongoing cost, and your call to make in AWS. Reading them runs Logs
Insights queries, which AWS bills at ~$0.005/GB scanned, so it has its own
opt-in consent the same way `--reconcile` does. Needs a `vpc` resource with a
resolved ID in the IaC, plus `ec2:DescribeFlowLogs`,
`ec2:DescribeNetworkInterfaces`, `ec2:DescribeSubnets`, `ec2:DescribeVpcs`,
`logs:StartQuery` and `logs:GetQueryResults`.

Each measured total is folded into the headline monthly figure and its ±1σ
range as its own synthetic line (`cross_az_data_transfer`,
`igw_internet_egress`, `inter_region_egress`), with a dedicated **MEASURED
DATA TRANSFER** section breaking each down per source resource or destination
region (plus an "unattributed" line for ENIs that map to no resource in the
IaC). Same-AZ transfer is free and never counted; traffic to public AWS
endpoints in the same region (e.g. S3, DynamoDB) is not counted — free or
regional depending on the service, and Flow Logs can't tell which. No usable
Flow Log ⇒ these dimensions stay unpriced and disclosed, exactly as without
the flag. When a flow log's format carries the `pkt-dst-aws-service` field,
the NAT-Gateway → Gateway-VPC-endpoint recommendation also upgrades from a
$0 ceiling nudge to a measured eliminable amount.

## Reconcile with your real bill

```
cloudcosttree analyze ./my-infra.tf --reconcile
```

`--reconcile` (**Pro**) is the backward-looking companion to `--with-usage`.
Where `--with-usage` asks *"what would the observed usage cost at list
price"*, `--reconcile` asks *"what did AWS actually charge"* — and lays that
next to the IaC estimate:

```
RECONCILIATION (estimate vs. actual)
Window: last 14 days (2026-08-17 to 2026-08-31), scaled to a monthly run-rate

IaC estimate (list price):  $509.23/month
AWS actually billed:        $472.80/month
Delta:                      -$36.43/month

Per EC2 instance:
  web-1                      est $61.32 → actual $54.10  (Δ -$7.22)

By service:
  Amazon Elastic Compute Cloud - Compute   est $180.00 → actual $150.00  (Δ -$30.00)
  Amazon Route 53                          est —        → actual $12.00   (Δ +$12.00)

Billed, but not in your IaC:
  Amazon Route 53 — $12.00/month
```

It reads **Cost Explorer** with your own read-only credentials:
`ce:GetCostAndUsage` (grouped by service — always available) and, for
per-EC2-instance detail, `ce:GetCostAndUsageWithResources` (needs your
account to have turned on resource-level Cost Explorer data in the Cost
Explorer settings page; without it, reconciliation is at service resolution
and says so). Cost Explorer bills **$0.01 per request**, so results are
cached ~12 h under `~/.cloudcosttree/actuals`; `--reconcile-refresh` forces
a re-query.

- `--reconcile-days <n>` widens the window past the default 14. Per-instance
  detail isn't retained past 14 days, so a longer window drops to
  service-level resolution (and says so).
- `--cost-allocation-tag <key>` adds a per-tag-value roll-up — your IaC's
  own resources bucketed by that tag key next to Cost Explorer's per-value
  total, with `(untagged)` for spend carrying no value for that key.
  Activate the tag as a cost-allocation tag in the AWS billing console
  first, or Cost Explorer returns nothing for it.
- With `--accounts`, `--reconcile` reads Cost Explorer once per distinct
  role and merges the reports (per-instance detail requires every account
  to have opted in).
- `--reconcile` also works on `diff`, lining the real bill up against the
  *current* (target) state.

The estimate–vs–actual delta report is the point: continuous reconciliation
of what the IaC intends against what AWS is really charging, including the
services in your bill that no resource in the IaC maps to. The top-level
monthly total in the rest of the report stays the list-price estimate — the
actual is shown alongside it, never silently substituted. This is a v1:
Cost Explorer only. CUR (Cost & Usage Report) ingestion for true line-item /
amortized history is a planned follow-up.

## What CloudCostTree does not claim

Even with `--with-usage` and `--reconcile`, some things are structurally out
of reach. The tool frames these rather than guessing at them:

- **Non-constant future usage** (a launch, a campaign, virality): external
  knowledge no metric contains. The `--with-usage` number is a projection
  at *constant observed usage* — for an event you already know about, use
  the what-if simulator instead.
- **Per-tree-node attribution of shared cost**: the variable (per-GB /
  per-request) part of a shared NAT/ALB needs opt-in flow logs that can't be
  gathered retroactively; the fixed hourly part is an allocation *policy*,
  not a fact. Shared cost is shown as its own line, never split silently.
- **Cross-AZ / inter-AZ, direct-to-internet and inter-region data transfer**:
  no CloudWatch metric separates the billable portion from free traffic.
  `--flow-logs` (Pro) prices all three from your existing VPC Flow Logs;
  without them they're left unpriced, and said so. Inter-region transfer over
  VPC peering / Transit Gateway / PrivateLink uses private addresses and stays
  unpriced even with `--flow-logs`.
- **Tax, credits, EDP/PPA negotiated terms, org-level tier position,
  non-AWS cost**: out of scope. The list-price line says "before Savings
  Plans / Reserved Instances / credits / tax"; `--reconcile`'s actuals come
  straight from AWS and do include whatever AWS itself included.

## What-if simulator

```
cloudcosttree analyze ./my-infra.tf --target aws_instance.web --instance-type m5.large
```

Simulates a change to one resource (`--target <address or name>`) and shows
the before/after cost, without touching your Terraform code. Every
declared, priced attribute has a matching flag: `--instance-type`/
`--instance-class`, `--os`, `--region`, `--count`, `--auto-scaling-min`/
`--auto-scaling-max`, `--root-volume-size`/`--root-volume-type` (EC2),
`--volume-size`/`--volume-type` (EBS), `--multi-az`/`--no-multi-az`,
`--rds-backup-retention`, `--allocated-storage`, `--iops`, `--throughput`,
`--snapshot-size`, `--nat-data`, `--nat-type`, `--data-out`/`--data-in`,
`--elastic-ips`, `--dynamo-rcu`/`--dynamo-wcu`/`--dynamo-mode`,
`--table-class`, `--lb-type`/`--lb-scheme`, `--retention-days`,
`--hours-per-month`, `--lambda-memory`, and more; run
`cloudcosttree analyze --help` for the complete, resource-scoped list.

### Multi-resource scenarios (`--scenario`)

```
cloudcosttree analyze ./my-infra.tf --scenario changes.yaml
```

`--target`/per-resource flags simulate a change to exactly one resource.
`--scenario <path>` simulates changes to **several** resources in one run,
applied in file order against the same evolving infrastructure: the
combined before/after reflects every entry together, not just the last
one:

```yaml
version: "1.0"
changes:
  - target: aws_instance.web
    flags:
      instance-type: m5.large
  - target: aws_ebs_volume.data
    flags:
      volume-type: gp3
      volume-size: 200
```

Every flag key/value under `flags:` is the same `--flag value` pair
accepted on the command line: nothing new to learn, just declared per
target instead of typed out as repeated `--target`/flag pairs (which the
CLI doesn't support directly: `--scenario` is the only way to change more
than one resource in a single what-if run). `--scenario` is mutually
exclusive with `-t`/`--target` and any individual what-if flag on the
command line: put every target's flags in the file instead.

### Structural changes (`add:`/`remove:`)

A `--scenario` entry can also synthesize a brand-new resource or delete an
existing one, instead of re-flagging one that's already declared:

```yaml
version: "1.0"
changes:
  - add:
      type: rds
      name: read-replica-1
      instance_type: db.r6g.large
      size_gb: 100
  - target: legacy-worker
    remove: true
```

`add:` declares the new resource with the exact same fields this tool's own
YAML/JSON schema uses for any resource (`type`, `name`, `instance_type`,
`size_gb`, ...): nothing new to learn there either. `type` and `name` are
required; `region` defaults to the infrastructure's own region if not given.
The synthesized resource has no `resource_id`/`arn` (nothing real exists yet
to have one) and renders ungrouped in the what-if tree (no module/stack
grouping): acceptable for simulating "what if I add a read replica"-style
questions, where the point is the cost delta, not where it'd land in a real
module tree. `remove: true` (with a `target`) deletes that resource instead;
neither `add:` nor `remove:` can be combined with `flags:` in the same
entry. `--write-changes` materializes `remove:` for every supported input
format: this tool's own YAML/JSON schema (splicing the matching resource
out, including one nested under another's `children:`) and Terraform/
Terragrunt HCL (deleting the whole `resource` block, resolved and
disambiguated across the source tree the exact same way a flag change is,
see [above](#writing-simulated-changes-to-disk---write-changes-pro)), except
a `count`/`for_each` resource, since one block backs every instance there
and deleting it would remove all of them, not just the one a `remove:` entry
names; that case is refused with a clear reason instead of guessed at.
`add:` stays unsupported for every format: an unsupported entry is listed
in `WHATIF_CHANGES.md`, the same way an unmapped flag or a non-literal
expression already is.

### Writing simulated changes to disk (`--write-changes`, Pro)

```
cloudcosttree analyze ./my-infra.tf --target aws_instance.web --instance-type m5.large --write-changes ./out
```

`--write-changes <dir>` goes one step further than the console report or
`--export`: it writes the simulated change into a **new** directory:
your original input is never opened for writing. Only the specific
attribute(s) that changed are patched; everything else (formatting,
comments, unrelated resources) is left untouched. Works with `-t`/`--target`
or `--scenario`, the same way `--export` does.

Not every input format this tool reads can be written back to, and even
within a supported format, not every change can be:

- **Supported**: Terraform (`.tf`, including local modules) and Terragrunt:
  both are, underneath, a directory of HCL this tool copies and then
  patches in place, so `<dir>` must be a new, empty directory (Terraform
  evaluates the whole directory as one config, so there's no such thing as
  copying "just the one changed file"); plus this tool's own YAML/JSON
  schema, which is actually the *easiest* of the three: it has no
  variables or expressions at all, so there's no ambiguity about what's
  safe to overwrite, and (unlike Terraform/Terragrunt) it writes a single
  new file, `<name>_cct.<ext>`, next to the original: `<dir>` can be the
  same directory the input already lives in, and doesn't need to be empty,
  since the `_cct` suffix can never collide with a file you actually
  authored. Two caveats specific to this schema: the output is a fresh
  re-marshal of the fully-resolved result, not a byte-for-byte patch of
  your original file, so hand-written comments aren't preserved, and a
  field this tool normalizes automatically (e.g. a per-resource `region`,
  backfilled from the top-level one) may show up explicitly in the output
  even if you never wrote it yourself.
- **Not supported, structurally** (not "not yet"): a raw `.tfstate` file, a
  `pulumi stack export`, and a CDK-synthesized template. None of these is
  code a person hand-edits and re-applies: they're deployed-state
  snapshots or build artifacts. A registry/remote Terraform module (a
  `module` block whose `source` isn't a local path) is out of scope for the
  same reason: there's no local file to patch.
- **Not supported yet, but plausible later**: a hand-written CloudFormation
  template (JSON/YAML, *not* CDK-synthesized output) is real source in
  principle, but needs its own intrinsics-aware patcher (`Ref`/`Fn::GetAtt`/
  `Fn::Sub` play the same "don't touch this" role `var.foo` plays for
  Terraform), a separate implementation, not shipped yet.
- **Even in a supported format**: only a plain literal attribute is ever
  overwritten. An attribute set to a variable, a reference, or any other
  expression is left exactly as-is. Every change that couldn't be safely
  written (wrong format, non-literal, unmapped flag, ambiguous match) is
  listed with a specific reason in `<dir>/WHATIF_CHANGES.md`
  (`WHATIF_CHANGES_cct.md` for the own-schema case, matching its `_cct`
  file-naming convention above), never silently dropped.
- **Terragrunt's idiomatic `inputs = { ... }` pattern** (a module declares
  `var.instance_type`, the unit's own `terragrunt.hcl` supplies the real
  value) is handled as a fallback: when a module attribute turns out to be
  exactly `var.<name>`, this tool checks whether the owning unit's
  `terragrunt.hcl` has a literal `inputs.<name>` and patches that instead
  of giving up. One trade-off worth knowing: since there's no way to edit
  a single key inside an `inputs = {...}` object without rebuilding the
  whole thing, this reformats the entire `inputs` block (key order can
  change) rather than touching one line: every *other* key's value is
  still required to already be a plain literal too, or this declines the
  whole fallback rather than guess.

This is a **CloudCostTree Pro** feature: see [Free vs Pro](#free-vs-pro).
On Free, `--write-changes` is accepted but writes nothing: the report
renders exactly as it would without the flag, plus an explicit upgrade
note.

## Optimize

```
cloudcosttree analyze ./my-infra.tf --optimize
```

Every dollar figure in [FinOps recommendations](#finops-recommendations)
above is computed by re-pricing the resource with one specific attribute
changed: `--optimize` closes the loop between "here's a recommendation"
and "here's the change applied": it auto-builds a what-if scenario from the
FinOps recommendations the report is *already showing* (the same tier-capped
list: top 3 Free, top 15 Pro), keeps only the ones safe to apply
mechanically, and runs it through the exact same simulation engine
`--scenario` uses, same combined before/after report, same
`--write-changes` to materialize it to a new file/directory. Nothing new to
learn: `--optimize` is sugar for a `--scenario` file this tool would have
written for you.

"Safe to apply mechanically" means a same-resource attribute change with no
architecture/availability trade-off to weigh, or a deletion AWS itself
already confirmed is unused:

- **Applied automatically**: gp2 → gp3 (EBS and RDS/RDS Cluster storage),
  provisioned IOPS (io1/io2) → gp3, previous-generation instance type →
  current generation, RDS backup retention capped at 30 days,
  non-production resources rescheduled to business hours, and, under
  `--with-usage` (Pro), confirmed orphaned EBS volumes/snapshots, confirmed
  empty-target-group load balancers, and confirmed unassociated Elastic IPs
  (deleted, at their full cost).
- **Offered, never auto-applied** (shown, but excluded from what
  `--optimize` runs, same "confirm this first" posture these already have
  in the plain FinOps list): x86 → Graviton (a CPU architecture change),
  removing RDS Multi-AZ (a high-availability change), DynamoDB provisioned →
  on-demand (this tool doesn't model on-demand's real per-request rate yet,
  so the estimate compares against a flat assumed-low-capacity baseline
  instead of your table's real traffic — a busy table can genuinely cost
  more on-demand, so this always needs a human to confirm real utilization
  first), real CPU-based right-sizing under `--with-usage` (a
  measured-but-inferred resize, with a possible Reserved Instance stranding
  trade-off), and Lambda memory right-sizing under `--with-usage` (a
  measured, real `--lambda-memory` what-if change, but Lambda's CPU
  allocation scales with memory_size, so a smaller function can run
  measurably slower, a trade-off worth confirming before applying).
- **Not representable as a single what-if change at all** (untouched,
  same as today): a Reserved Instance/Savings Plan candidate (a purchase
  decision, not an attribute), an EC2 fleet without an Auto Scaling Group, a
  NAT Gateway → NAT instance swap (a resource-type change, not a single
  attribute), a fleet size outlier, and every governance nudge (naming,
  tags, no dollar figure to act on).

`--optimize` finds nothing safe to apply → the run fails clearly (exit 1),
the same way an empty or no-match `--scenario` already does, never a
silent no-op. Mutually exclusive with `-t`/`--target`, an individual what-if
flag, and `--scenario`: put every other combination the what-if
[flags](#what-if-simulator)/[`--with-usage`](#usage-aware-finops---with-usage)/
[`--write-changes`](#writing-simulated-changes-to-disk---write-changes-pro)
sections already document on top of it exactly as you would for a manual
scenario run.

**Free**, like every what-if simulation: `--optimize` only ever draws from
the recommendations the report already discloses for your plan, so it can
never apply more than a Free account can already see. `--write-changes` on
top stays **Pro**-gated exactly as it already is; a confirmed-orphan
deletion previews, simulates, and now materializes to disk correctly under
`--optimize` for every supported input format, the same
`count`/`for_each` exception a hand-written `remove: true` scenario entry
has applies here too (see
[above](#writing-simulated-changes-to-disk---write-changes-pro)).

The VS Code extension's what-if panel exposes the same thing as an
"⚡ Optimize" button; see [VS Code extension](#vs-code-extension) below.

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

`policy init --pack <name>` writes a curated, ready-to-run pack instead of
the default 6-policy template: same DSL, just different starting content:

| Pack | Focus |
|---|---|
| `well-architected` | Required tags, no generic names, RDS backup retention ≥7 days, an ownership-coverage cap (`count(...)`), a whole-infrastructure cost ceiling |
| `finops-guardrails` | Bans previous-generation instance types (t2/m4/c4/r4) outright, a per-resource cost cap, NAT Gateway low-traffic, and a stricter, blocking (`action: error`) total-cost cap |

```
cloudcosttree policy init --pack well-architected
cloudcosttree policy init --pack finops-guardrails
```

An unrecognized pack name is rejected with the current list of valid names
rather than silently falling back to the default template.

Condition language (evaluated per-resource by default):

| | |
|---|---|
| Fields | any resource attribute (`instance_type`, `monthly_cost`, `region`, `size_gb`, `multi_az`, `is_generic_name`, …) or a tag via `tags.<Key>` |
| Logic | `and`, `or`, `not` |
| Comparisons | `==` `!=` `<` `<=` `>` `>=` |
| Membership | `in [...]` / `not in [...]` |
| Presence | `<field> exists` (e.g. `tags.Owner exists`) |

`resource_type` (optional) restricts a policy to one resource type; omit it
to check every resource. `action` is `warn` \| `error` \| `deny`: the
latter two fail the run with a non-zero exit code, which is what CI/CD
gating builds on. `severity` (`critical`/`high`/`medium`/`low`) controls
display order and the icon shown in the violations section.

`scope` (optional) is `resource` (the default above) or `aggregate`. An
`aggregate`-scoped policy is checked exactly once against
whole-infrastructure facts instead of per-resource: `total_monthly_cost`
and `resource_count`, the only two plain fields the aggregate context
exposes, producing at most one violation with no single resource attached
to it. Mutually exclusive with `resource_type` (there's no single resource to
match a type against):

```yaml
- name: "Total infrastructure cost cap"
  scope: "aggregate"
  condition: "total_monthly_cost < 10000"
  action: "warn"
  severity: "high"
```

An aggregate condition can also use `count(<condition>)`: the one
exception to "aggregate only sees whole-infrastructure numbers": it
evaluates `<condition>` against every resource individually (the same
condition language as a `resource`-scoped policy, `and`/`or`/`not`/`in`/
`exists` included) and yields how many matched, so a single aggregate policy
can cap *how many* resources fail an otherwise per-resource check:

```yaml
- name: "Most resources must have an Owner tag"
  scope: "aggregate"
  condition: "count(not (tags.Owner exists)) <= 5"
  action: "warn"
  severity: "medium"
```

`count(...)` is a special form, not a general function-call grammar: it's
only meaningful inside an aggregate condition (evaluating it in a
`resource`-scoped policy fails with an explicit error, rather than silently
returning 0).

Policy evaluation (cost guardrails, tag/FinOps rules) is a **CloudCostTree
Pro** feature: see [Free vs Pro](#free-vs-pro). On Free, `policy check`
requires an upgrade, and policy checks embedded in tree/analyze/diff/ci
silently evaluate zero policies (the cost report stays informational;
nothing can fail a build).

**`--max-monthly-cost <n>`** is a shortcut for exactly the aggregate cost
cap above, without writing a `policies.yaml` at all: `tree`/`analyze`/`diff`
and `ci report`/`check`/`diff` all accept it, folding a synthetic
`total_monthly_cost <= <n>` (`action: error`) policy into the same
evaluation as `--policies`, so it fails the run the same way any other
blocking policy does. Same **Pro** gate as every other policy check above:
unlike a `policies.yaml` violation, which just silently evaluates to
nothing on Free, passing `--max-monthly-cost` on Free prints an explicit
note that it wasn't enforced, so the flag never *looks* like it worked when
it didn't.

## Local apply guard (`guard`)

```
cloudcosttree guard -- terraform apply
```

Not the [CI/CD](#cicd) `Cost Guard` GitHub Actions workflow below: that
gates a pull request; this gates a real `terraform apply` on your own
machine, at the moment you'd actually run it, for the (common, for this
project's target audience) case where there's no CI/CD pipeline in the loop
at all yet. Run from the same directory you'd run `terraform apply` from:
`guard` runs `terraform plan` itself, checks that exact plan against your
policies, then applies that *same saved plan*, never a fresh one, so
nothing can drift between the check and the apply.

Default behavior is warn-only: a blocking policy violation (`action: error`
or `deny`) prints, but `terraform apply` still runs. `--block` opts into
actually gating it. This is deliberate: a plan-parsing edge case or a
false positive blocking a real infrastructure deploy is far more costly
than one appearing in a report, so blocking is opt-in, never the default:

```
cloudcosttree guard --block -- terraform apply
```

Same **CloudCostTree Pro** gate as `policy check`: `guard`'s only value is
policy enforcement, which is Pro-only on every other command too. The
wrapped command after `--` must be exactly `terraform apply`; this isn't a
generic subprocess wrapper.

## Cost Score

Every `tree`/`analyze`/`diff` run computes a **Cost Score**: a 0-100 number
plus a letter grade (A-F) rolling up every FinOps recommendation and policy
violation found in that run, weighted by severity and normalized by resource
count so a 200-resource stack with a couple of low-severity nudges doesn't
score worse than a 3-resource stack with the same absolute findings:

```
$ cloudcosttree ./my-infra.tf

...
──────────────────────────────────────────────────────────────
COST SCORE: B (82/100)
──────────────────────────────────────────────────────────────
```

Unlike real Reserved Instance/Spot savings or policy enforcement, the Cost
Score is **available on every plan**: it's meant as a quick, shareable "is
this stack healthy" signal, not something gated behind an upgrade. It's
computed from each finding's *real* severity, not the Free-tier display
redaction some FinOps rules apply to their dollar figure (see
[FinOps recommendations](#finops-recommendations) above), a real issue's
severity doesn't soften just because its exact $/mo figure is hidden from a
Free report.

It appears in every report format this tool produces: the console (`tree`/
`analyze`/`diff`), every `--export` format (`md`/`csv`/`json`/`html`/
`pr-comment`/`slack`), and (most usefully) `history save`/`list`/`compare`
(see [History](#history) below), so a team can track whether a stack is
getting healthier or worse over time the same way it already tracks cost:

```
$ cloudcosttree history compare @previous @latest
...
Cost Score:         78/C -> 85/B (+7)
```

## History

```
cloudcosttree history save prod-2026-07 ./my-infra.tf
cloudcosttree history save prod-2026-07 ./my-infra.tf --usage usage.yaml
cloudcosttree history save prod-2026-07 ./my-infra.tf --with-usage
cloudcosttree history list
cloudcosttree history trend [-last <n>]
cloudcosttree history compare <name-or-id> <name-or-id>
cloudcosttree history compare <name-or-id> <name-or-id> --group-by-tag <key>
cloudcosttree history delete <name-or-id>
cloudcosttree history export <name> <path>
cloudcosttree history import <path>
```

Snapshots a cost tree locally (no account, no upload) so you can compare
cost (and [Cost Score](#cost-score)) over time the same way `diff`
compares two files. 180-day retention, auto-pruned, disk hygiene, not a
plan limit; identical on Free and Pro. Saving with `--usage <path>` (see
[Real usage volume](#real-usage-volume---usage-file) above) or `--with-usage`
(live CloudWatch data, Pro — see [Usage-aware
FinOps](#usage-aware-finops---with-usage) above) also records each
usage-billed resource's real consumption in the snapshot, which `compare`
can later attribute a delta to directly — see [Cost delta
attribution](#cost-delta-attribution) below.

While `compare` diffs two snapshots, `trend` reads every saved snapshot (or
just the last N, via `-last`) and prints an ASCII sparkline of total
monthly cost and Cost Score across all of them, so you can see the shape of
a stack's cost history at a glance instead of comparing pairs by hand:

```
$ cloudcosttree history trend
▁▂▂▄█  $850.00/month -> $1,340.00/month  (2026-06-01 -> 2026-08-01)
Delta:       +$490.00/month (+57.6%)   Range: $850.00 - $1,340.00/month
Cost Score:  █▆▅▃▁  92/A -> 68/D
```

`history export`/`history import` copy that same snapshot JSON file to/from
an arbitrary path, so a snapshot can be shared with a team via git, S3, or
any storage already in use, no hosted backend needed. Not to be confused
with the `--export <format>[:path]` flag on `list`/`compare`/`save`/`trend`
below, which renders a human-readable report instead of copying the raw
snapshot.

### Cost delta attribution

`history compare` labels each changed resource's delta with a **cause**,
where it can tell: a $/mo swing between two snapshots doesn't always mean
your infrastructure changed:

```
Changed (1):
  ~ web [ec2] (price change)          +$4.80/month
```

- **`config change`**: the resource's instance type (or, for EBS/RDS-style
  resources, its size) itself changed between snapshots.
- **`price change`**: the instance type is identical, but the AWS price
  catalog was refreshed between the two `history save` runs (this tool's
  published catalog updates on its own ~15-day cadence, see
  [Install](#install)): the resource didn't change, its rate did.
- **`usage change`**: for the resources AWS bills purely by consumption
  (Lambda, SQS, SNS, API Gateway, CloudFront, ...), real usage moved between
  snapshots enough to explain the delta on its own, with no config or
  catalog change in play. Requires both snapshots to have been saved with
  `history save --usage <path>` (see [Real usage
  volume](#real-usage-volume---usage-file) above) or `--with-usage` (Pro) —
  without one of those, these resources have no usage fingerprint recorded
  and a real consumption
  change falls back to unlabeled, same as before this bucket existed. When
  both snapshots were saved with `--with-usage`, "enough to explain the
  delta" is a real measured threshold — this tool's own confirmed
  day-to-day variance for that resource at each save time (see [Confidence
  range on usage-priced
  estimates](#usage-aware-finops---with-usage) above), not a flat
  percentage guess; a snapshot saved with a `--usage` file instead (no
  variance signal at all) still falls back to that flat guess.
- No label at all: the cause can't be determined (a snapshot saved before
  this attribution existed, one or both saved without `--usage` for a
  usage-billed resource, or a real change this tool doesn't fingerprint
  yet, like `iops`). Never guessed; an unlabeled delta is exactly as
  informative as before this feature existed, nothing is silently
  misattributed.

When the catalog itself changed between the two snapshots being compared, a
note above the resource list calls that out explicitly, since it affects
how to read every `price change`-labeled line below it. Config and price
are checked first, so a resource whose usage moved *and* whose catalog
also happened to refresh in the same window is still labeled `price change`
— usage is a fallback attribution, not a competing one.

### Cost allocation by tag

`history compare --group-by-tag <key>` answers a different question than
the cause attribution above: not "why did this resource's cost change,"
but "why did the total cost attributed to `<key>=<value>` change" — e.g.
`--group-by-tag team` for `team=payments`. A resource's own cost is
tag-independent, so re-tagging it never explains its own delta; this is a
separate, additive report alongside the usual compare output, not a new
value on the existing cause label:

```sh
cloudcosttree history compare before-migration after-migration --group-by-tag team
```

```
COST ALLOCATION BY TAG: team
  payments    $600.00/month -> $420.00/month (-$180.00/month)
  platform    $300.00/month -> $480.00/month (+$180.00/month)

Moved (1):
  ~ web [ec2] moved payments -> platform      $60.00/month -> $60.00/month
```

Four distinct things can move a group's total, reported separately:

- **Group totals**: each tag value's aggregate cost in both snapshots,
  independent of whether any individual resource moved between groups.
- **Moved**: a resource present in both snapshots whose tag value itself
  changed — a reallocation, not new spend.
- **Added / Removed**: genuine infrastructure changes (no match at all in
  the other snapshot), scoped to whichever group the resource's tag puts
  it in — never counted as a move.
- **Changed**: a resource that stayed in the same group both times, but
  whose own cost moved for the usual config/price/usage reasons (see [Cost
  delta attribution](#cost-delta-attribution) above — this reuses the same
  cause labels).

The tag key has no default and is never guessed — case-sensitive exact
match against each resource's tags, same as this tool's policy tag
conditions (`tags.<Key>`, see [Policies](#policies) above).
Resources missing the tag key entirely are grouped under `(untagged)`,
never silently dropped from the totals. Only included in `--export json`
for now; the `md`/`csv`/`html`/`pr-comment` exports don't have a by-tag
table yet.

### Cost drift alerts in CI

`history compare` can fail the run (exit 1) when total cost *increased*
past a threshold, a decrease never blocks, this is a regression gate, not
a general change alert:

```sh
cloudcosttree history save "run-$CI_COMMIT_SHA" ./my-infra.tf
cloudcosttree history compare @previous @latest --fail-on-drift-pct 20
```

`@latest`/`@previous` resolve to the most, and second-most, recently saved
snapshot, so a CI job that saves one new snapshot per run never has to
track two names itself. `--fail-on-drift-pct <n>` and `--fail-on-drift-abs
<n>` are independent and can be combined: the percent check alone can't see
a brand-new, previously-untracked stack (0 → nonzero is a 0% delta, not a
percentage), so pair it with an absolute dollar threshold to catch that
case too. Works on both plans: this isn't a policy-engine check, just a
threshold on `history compare`'s own output.

Pipe the same drift check straight to a Slack channel by exporting `slack`
to your Incoming Webhook URL instead of (or in addition to) failing the
build:

```sh
cloudcosttree history compare @previous @latest --fail-on-drift-pct 20 \
  --export slack:$SLACK_WEBHOOK_URL
```

## Exports

`--export <format>[:path]` on `tree`/`analyze`/`diff` (omit `:path` to
print to stdout, pipeable): `md`, `csv`, `json`, `html`, `pr-comment`
(GitHub-flavored, what `ci diff` posts to a PR), or `slack` (Slack Block
Kit JSON). Unlimited on both tiers.

`slack:<path>` writes the Block Kit payload to a local file, same as any
other format, handy for previewing the message before wiring it up for
real. `slack:<https://hooks.slack.com/services/...>` (anything starting
with `http://`/`https://`) instead **POSTs it directly** to that Slack
Incoming Webhook: no account, no OAuth app, nothing hosted by us in the
loop: the webhook URL is created entirely inside your own Slack workspace
and typically lives as a CI secret (`$SLACK_WEBHOOK_URL` above). Works
identically on every command that already supports `--export`
(`tree`/`analyze`/`diff`, `history save`/`list`/`compare`, `ci
report`/`check`/`diff`): pair it with `history compare
--fail-on-drift-pct` (cost drift) or `ci check` (policy violations) to
turn an actionable event into a Slack message instead of a passive digest
nobody reads.

## CI/CD

See [CI.md](CI.md) for the full guide: GitHub Actions (a ready-to-use
composite action, published at
[`rulssss/cloudcosttree`](https://github.com/rulssss/cloudcosttree) so it
only ever downloads a prebuilt binary, never the private source repo),
GitLab CI, Azure Pipelines, and Bitbucket Pipelines, JSON/Markdown output,
and PR annotations.
The dedicated `ci` command group (`report` never fails the build;
`check`/`diff` fail on a blocking policy violation) shares Free's
1,000-runs/month quota across a repo's pipelines (tracked per-repo
server-side on GitHub Actions, since a fresh runner every job has nothing
local to count against); Pro is unlimited, confirmed live on every run via
a `license-key` input, no per-machine activation seat is spent doing this,
unlike the normal desktop `license activate` flow.

## IAM policy generator

```
cloudcosttree iam ./infra/                          # Terraform directory (static scan, no init/plan/credentials)
cloudcosttree iam ./infra/ --plan plan.json          # + a real terraform show -json plan for precise per-resource actions
cloudcosttree iam ./infra/ --output json -o policy.json
cloudcosttree iam cfn-template.json                  # CloudFormation
cloudcosttree iam pulumi-export.json                 # `pulumi stack export > pulumi-export.json`
```

Answers a different question than the rest of this tool: not "what will
this cost" but "what IAM permissions does deploying this actually need" —
the least-privilege policy for a deployer role, worked out from the same
Terraform/CloudFormation/Pulumi input, without ever contacting AWS.
Terragrunt/Atmos aren't scanned separately: both resolve to a real
Terraform module directory, so pointing this at that resolved directory is
enough.

A plain directory scan (no `--plan`) can't tell create from update from
delete, so it grants a resource type's full CRUD action set; a real
Terraform plan (`--plan`, or a `terraform show -json` file passed directly)
narrows that to exactly the actions the actual planned change needs.
CloudFormation and Pulumi input are always scanned statically (a template
alone, or a stack export, carries no plan-level action detail the way a
Terraform plan does).

**`Resource` scoping:** every generated policy uses `"Resource": "*"`. The
`Action` list is real and correctly scoped to the specific IAM API calls
each resource type needs; the `Resource` element is not narrowed to the
exact ARNs a deployment declares (a `s3:DeleteBucket` grant works against
any bucket in the account, not just this one). Per-resource ARN scoping is
a planned Pro capability and is not implemented yet — today the full,
`Resource: "*"` generator is the same on both tiers. Review the output
before attaching it to any real IAM identity, same as you would any
least-privilege tool's starting point.

**Privilege-escalation review:** a least-privilege deployer policy still
grants real permissions, and some of them are the building blocks of
documented IAM privilege-escalation techniques — `iam:PassRole` alongside a
compute-launch action (`lambda:CreateFunction`, `ec2:RunInstances`,
`glue:CreateDevEndpoint`, `cloudformation:CreateStack`, SageMaker,
CodeBuild), or a direct principal-mutation action (`iam:AttachRolePolicy`,
`iam:PutRolePolicy`, `iam:CreateAccessKey`, `iam:UpdateAssumeRolePolicy`,
…). Whenever the generated `Action` set contains such a combination, `iam`
prints a **Privilege-escalation review** block naming the technique, the
exact actions, and which input resource pulled them in. It's appended to
the text report; for `--output json` the policy document stays a clean,
attachable `{Version, Statement}` (a `Warnings` key would fail `aws iam
create-policy` validation), so the review goes to stderr — and, when the
policy was written with `-o policy.json`, also to a sibling
`policy.privesc.txt` beside it, so a consumer that keeps only the file (the
VS Code extension's **Generate IAM Policy**, a CI step) still gets the
disclosure. The technique list is curated from public, citable catalogs —
[Rhino Security Labs' IAM privilege-escalation research](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation-part-1/)
and [NCC Group's PMapper](https://github.com/nccgroup/PMapper) — and every
action in it is cross-checked against this tool's own mapping table. This
is a safety disclosure, not a Pro feature: it runs identically on both
tiers. It's expected output for a deployer that manages IAM or hands roles
to compute — the point is that you attach such a policy knowing it, having
restricted who can assume the deployer identity and narrowed `Resource`
first.

## VS Code extension

[vscode-extension/](vscode-extension/) adds an in-editor cost tree,
what-if panel, and diff view on top of the same CLI (every number comes
from a real `cloudcosttree analyze --export json:-` call, no re-implemented
pricing/parsing logic); see its own README for setup.

The first time the extension activates on a given machine, a one-time,
dismissible notification offers "Run Demo", the same bundled example the
CLI's own `cloudcosttree demo` runs, opened in the panel with zero files or
AWS account needed. Never auto-runs without a click; shown at most once
(tracked in `context.globalState`), and always reachable afterward via the
Command Palette ("CloudCostTree: Run Demo").

The what-if panel mirrors both CLI what-if modes: "Apply What-If" previews
one resource's change (the `-t`/`--target` flow), and "＋ Add to Scenario"
(offered once a preview is showing) stages that same change alongside
others: "Run Scenario" then applies them all together in one combined
report, the UI equivalent of `--scenario`. Re-staging a resource already in
the list replaces its entry rather than duplicating it.

An EC2 resource's "Instance type" field and an RDS/RDS-cluster resource's
"Instance class" field open a native, searchable picker (VS Code's own
QuickPick, filtering live as you type) instead of a plain dropdown: the
real catalogs are large (1,300+ EC2 instance types, 250+ RDS instance
classes) and a dropdown that size doesn't scroll well or filter at all. The
list itself comes from a small internal `cloudcosttree list-instance-types`
CLI command that reads the real, currently-priced set straight out of your
resolved price catalog, never a hardcoded subset.

"Generate File (Pro)" materializes whichever what-if (single or scenario)
is currently showing as real file(s) via `--write-changes`: a new,
uniquely-named folder next to the original input, never the original
itself; see [What-if simulator](#what-if-simulator) for exactly which
input formats and attribute types this supports.

An "⚡ Optimize (N)" button appears above the FinOps list whenever at least
one recommendation carries a machine-actionable fix: the UI equivalent of
[`--optimize`](#optimize). Clicking it opens a checklist of every such
recommendation, pre-checked for the ones safe to apply mechanically and
left unchecked (with a "⚠ REVIEW FIRST" badge) for the ones that still ask
for your confirmation first (Graviton, Multi-AZ, an inference-based CPU
resize). "Apply Selected" builds a scenario from exactly what's checked and
runs it through the same "Run Scenario" pipeline above: "Generate File
(Pro)" then works on the result exactly as it would for a manually-staged
scenario.

The `cloudcosttree.withUsage` setting is the extension's opt-in bridge to
[`--with-usage`](#usage-aware-finops---with-usage) (Pro): turning it on
shows a one-time confirmation dialog (this is the one feature that calls
your own AWS account), then enriches Analyze/Compare the same way the CLI
flag does; see the extension's own README for the consent/credential
details.

A resource with a real [measured confidence
range](#usage-aware-finops---with-usage) shows a small `±` marker next to
its monthly cost in the tree (hover it for the real range) — in Analyze
mode, clicking the resource also shows the full range in the detail panel.
Compare's tree is read-only (no detail panel), so there the `±` marker's
tooltip is the only place the range appears.

"🛡️ Generate IAM Policy" is the UI for [the `iam` command](#iam-policy-generator)
above — reachable from the analysis panel's toolbar, the Command Palette,
and the explorer/editor right-click menu on any supported file or folder.
Unlike every other button here, it doesn't need a cost analysis open at
all (it's a fully standalone command); a click writes
`<name>_cct-iam-policy.json` next to the input and opens it, no save
dialog. Free on both tiers.

## Free vs Pro

Free is a generous, unlimited cost-visibility tool for local use: Pro adds
CI/CD scale, the ability to actually enforce governance, real-dollar
Reserved Instance/Spot pricing, and usage-aware right-sizing.

| | Free | Pro ($14.99/mo) |
|---|---|---|
| Analyses (tree/analyze/diff) | Unlimited | Unlimited |
| What-if simulations | Unlimited | Unlimited |
| Exports (md/csv/json/html/pr-comment/slack) | Unlimited | Unlimited |
| History (`history save`/`list`/`trend`/`compare`) | Unlimited, 180-day retention | Unlimited, 180-day retention |
| Cost Score (health grade rolling up FinOps + policy findings) | Included | Included |
| FinOps recommendations shown | Top 3 by impact | Top 15 by impact |
| Real usage volume for request/GB/event-billed resources (`--usage` file: Lambda, SQS, SNS, ...) | Included | Included |
| Real Reserved Instance $ savings | Unquantified nudge only | Real 1yr-no-upfront $/mo figure |
| Usage-aware FinOps (`--with-usage`: CloudWatch right-sizing + live Spot pricing + real Lambda cost correction) | Not included | Included |
| Measured data transfer (`--with-usage`: NAT / Transit Gateway processing + NAT internet egress from CloudWatch bytes) | Not included | Included |
| Commitment coverage (`--with-usage`: Savings Plan / Reserved Instance list-vs-effective, read from your account) | Not included | Included |
| Confidence range on the total (`--with-usage`: ±1σ measured usage variance) | Not included | Included |
| Reconcile against your real bill (`--reconcile`: Cost Explorer estimate-vs-actual delta) | Not included | Included |
| CI/CD runs (`ci report`/`check`/`diff`) | 1,000/month | Unlimited |
| Cost guardrails & tag/FinOps policies (`policy check`, and policy enforcement inside tree/analyze/diff/ci) | Not included: cost data stays informational | Unlimited, can fail a build on violation |
| Write simulated what-if changes to a new file/directory (`--write-changes`) | Not included | Included |
| Input format: Atmos (Cloud Posse) stacks | Not included | Included |
| IAM policy generator (`iam`, 1644 resource types) | Full policy, `Resource: "*"` | Full policy, `Resource: "*"` (per-resource ARN scoping planned) |
| Cloud provider support | AWS | AWS |
| VS Code extension | Included | Included |

History's 180-day retention (auto-pruned locally, see `pkg/history`) is disk
hygiene, not a plan limit: it's the same on both tiers. Custom/negotiated
[price books](#custom-price-books) (`--price-overrides`) are available on
both tiers too: a flat %-discount MVP, not a full purchase-type-aware
model. [`--optimize`](#optimize) is a what-if simulation like any other, so
it's Free too: it just never applies more than the FinOps list a given
plan already discloses (top 3 Free, top 15 Pro); writing its result to disk
still needs `--write-changes` (Pro), same as a manual scenario.

```
cloudcosttree license status     # see your current plan and usage
cloudcosttree license buy        # upgrade
cloudcosttree license activate <key>
```

Licensing is a signed, local usage record (HMAC, a tamper *deterrent*, not
a defense against a determined binary patch) plus a small Cloudflare Worker
(`paddle-license-worker/`) that fronts Paddle for activation/validation:
Paddle has no public, unauthenticated License API of its own, so the Worker
holds the Paddle secret key and exposes the same activate/validate/
deactivate JSON envelope. See `pkg/license`.

## Architecture

```
cmd/cloudcosttree/   CLI entrypoint, flag parsing, Free/Pro gating (license_gate.go)
pkg/parser/          Terraform (plan + state), Terragrunt, CloudFormation, Pulumi → model.Infrastructure
pkg/model/           The shared Resource/Infrastructure schema every parser/renderer speaks
pkg/cost/            PriceCatalog + Calculator: prices.json → a resource's/tree's $/mo
pkg/pricing/         update-prices/generate-prices: AWS Price List Bulk API → prices.json
pkg/usagefile/       --usage file: local, declarative volume overrides (every plan)
pkg/usage/           --with-usage: live CloudWatch/EC2 Spot/EBS/EIP/ELBv2/Savings Plan calls (Pro)
pkg/actuals/         --reconcile: Cost Explorer reads, disk cache, estimate-vs-actual matching (Pro)
pkg/finops/          Savings-recommendation rules (declared-config rules + usage-aware rules),
                    each optionally carrying a machine-actionable Fix --optimize consumes
pkg/policy/          Governance/cost policy DSL: parsing, condition evaluation, templates
pkg/score/           Cost Score: FinOps + policy findings → a 0-100/A-F health grade (every plan)
pkg/resourcespec/    Per-resource-type registry: which what-if flags apply to which
                    resource type, and their Terraform HCL attribute path
pkg/tree/            Rendering: tree/comparison/what-if views, every export format
pkg/writeback/       --write-changes (Pro): patches a copy of the source with a
                    what-if simulation's result, never the original
pkg/history/         Local cost-snapshot storage + comparison (including Cost Score trend)
pkg/ci/              CI/CD-shaped report/check/diff output
pkg/license/         Free/Pro state, quotas, license Worker client
paddle-license-worker/ Cloudflare Worker fronting Paddle for activation/validation (see above)
vscode-extension/    Thin UI layer over the CLI (no duplicated pricing/parsing logic)
```

`data/prices.json` is the one artifact that ties `pkg/pricing` (writer) and
`pkg/cost` (reader) together: a per-region snapshot of on-demand + (Pro)
Reserved Instance rates, refreshed periodically by this project's own
automation and fetched by end users as a plain public file: the only
CloudCostTree capability that needs an AWS account of its own is
`--with-usage`, and that account is always the end user's, never this
project's.

That automation itself (`generate-prices`, run by
`.github/workflows/update-prices.yml`, not exposed to end users) fetches
the entire catalog (EC2 included) from AWS's public, unauthenticated
**Price List Bulk API**: static per-region JSON files with no per-account
rate limit, in place of AWS's rate-limited `pricing:GetProducts` Query API
this project used until this pass. `generate-prices` itself now needs no
AWS account/credentials of its own at all. EC2's bulk file (47-480MB per
region, it also covers EBS, NAT Gateway, and Dedicated Hosts, since those
bill under the same `AmazonEC2` service code AWS-side) is large enough that
fetching every region's copy at once would spike memory well past what a
CI runner should need, so `pkg/pricing/bulk.go`'s `ec2BulkGate` serializes
just that one service's downloads across regions; every other service
still fetches fully concurrently.

Because a bulk file carries a service's *entire* regional catalog rather
than only the specific types this project happened to query for, instance
coverage widened across the board at no extra fetch cost, replacing
hand-curated lists with real discovery
(`effectiveRDSInstanceClasses`/`effectiveEC2InstanceTypes` in
`pkg/pricing/service_rds.go`/`service_ec2.go`, `emrEligibleInstanceTypes`
in `pkg/pricing/regions.go`):

| | Before | Now (us-east-1) |
|---|---|---|
| RDS instance classes | ~19 curated | 251 discovered |
| EC2 instance types | ~53 curated | 1,300+ discovered |
| EMR instance types | 10 curated | 42 (every current-gen, non-burstable, ≥.xlarge EC2 type, EMR's own real minimum) |

## License

Proprietary: all rights reserved. Not open source; no public
contribution/license grant is implied by this repository being readable.
