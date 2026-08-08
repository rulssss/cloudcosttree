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

## Who this is for

CloudCostTree targets small/medium projects that want a simpler, cheaper
pricing model and a lightweight, single-binary tool for cost visibility —
today that means AWS, where it prices ~85 resource types with real,
fetched-from-AWS rates (see [Supported AWS
resources](#supported-aws-resources) below).

For context: AWS itself has 240+ services; everything this tool doesn't
price is either not a fixed-capacity "resource" a cost tree can represent
at all (most of AWS's usage-billed services — Textract, Rekognition, Step
Functions, and similar have no per-resource flat rate to price against,
only per-call/per-event billing), or just hasn't been mapped yet.

## Known limitations at a glance

The full picture lives in [Supported AWS resources](#supported-aws-resources)
and the sections below, but the short version: **AWS-only, no multi-cloud**;
an Auto Scaling Group using `mixed_instances_policy` stays unpriced from
declared config alone (`--with-usage` resolves it from real AWS data — see
below); CloudFormation input never carries a real post-apply
resource ID by itself (unlike Terraform/Pulumi input, which always does) —
`--with-usage` enrichment needs the extra `--stack-name <name>` flag to
resolve one live, since a plain template has no state of its own to read it
from; and Amazon Managed Grafana / most of AppStream 2.0's fleet
configurations aren't mapped. Everything else this tool doesn't price is
either genuinely free
(a VPC, a security group) or just hasn't been mapped yet — see below for the
full, honest list of what that covers and why.

## Table of contents

- [Who this is for](#who-this-is-for)
- [Known limitations at a glance](#known-limitations-at-a-glance)
- [Install](#install)
- [Commands](#commands)
- [Input formats](#input-formats)
- [Supported AWS resources](#supported-aws-resources)
- [FinOps recommendations](#finops-recommendations)
- [Real usage volume — `--usage` file (every plan)](#real-usage-volume---usage-file)
- [Custom price books (every plan)](#custom-price-books)
- [Real Reserved Instance savings (Pro)](#real-reserved-instance-savings)
- [Usage-aware FinOps — `--with-usage` (Pro)](#usage-aware-finops---with-usage)
- [What-if simulator](#what-if-simulator)
- [Policies](#policies)
- [Local apply guard — `guard` (Pro)](#local-apply-guard-guard)
- [Cost Score](#cost-score)
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
AWS account or credentials, and touches no network at all. The commands
that do touch the network, each opt-in: `update-prices` (fetches the
project's published catalog over HTTPS), the Pro `--with-usage` flag
(your own AWS credentials), `license buy`/`activate`/`status` (the
license service), and `--export slack:<https://...>` (POSTs to your own
Slack webhook URL, if you pass one).

The published catalog itself refreshes on a ~15-day cadence (a weekly cron
job that skips itself when `data/prices.json` is still fresh — see
`.github/workflows/update-prices.yml`), so a freshly-installed binary's
bundled rates are never more than ~2-3 weeks stale; run
`cloudcosttree update-prices` yourself at any time to force an immediate
refresh.

## Commands

```
cloudcosttree <infrastructure_file> [options]                       # tree view
cloudcosttree analyze <infrastructure_file> [what-if flags] [options] # what-if simulation, FinOps, policies
cloudcosttree diff <baseline_file> <current_file> [options]          # compare two states
cloudcosttree update-prices [options]                                # refresh the AWS price catalog (no AWS account)
cloudcosttree policy init|check|list|validate                        # governance/cost policies
cloudcosttree usage init                                             # scaffold a --usage volume-override file
cloudcosttree ci report|check|diff                                   # CI/CD-friendly output (see CI.md)
cloudcosttree history save|list|compare|delete|export|import         # track cost over time
cloudcosttree license buy|activate|status                            # CloudCostTree Pro
cloudcosttree guard -- terraform apply                               # local apply-time policy gate (not the CI Cost Guard workflow)
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
| `--dry-parse` | (`tree` mode only) Validate the parser recognizes the file and report resource count/types, no pricing — see [Commands](#commands) below |
| `--baseline <path>` | Baseline file for `diff` |
| `--policies <path>` | Governance/cost policies to check (falls back to `./policies.yaml`, then `~/.cloudcosttree/policies.yaml`) |
| `--usage <path>` | Declare real expected monthly traffic for request/GB/event-billed resources (Lambda, SQS, ...) — see below. Every plan, no AWS account needed |
| `--price-overrides <path>` | Apply your own negotiated/EDP discount on top of the published catalog — see [Custom price books](#custom-price-books) below. Every plan, no AWS account needed |
| `--include-governance` | Also show governance-only FinOps findings (naming/tags) alongside real savings |
| `--with-usage` | (`analyze` only, **Pro**) enrich with real CloudWatch utilization + live Spot pricing — see below |
| `--stack-name <name>` | (`analyze` only, with `--with-usage`, CloudFormation input only, **Pro**) the deployed stack name, needed to resolve real resource IDs for a CloudFormation template — see below |
| `--scenario <path>` | (`analyze` only) Simulate changes to several resources at once from a YAML file — see [What-if simulator](#what-if-simulator) below |
| `--write-changes <dir>` | (`analyze` only, **Pro**) Write a what-if simulation's result to a new file/directory, never the original — see [What-if simulator](#what-if-simulator) below |
| `--export <format>[:path]` | Write a report in `md`/`csv`/`json`/`html`/`pr-comment`/`slack` (omit `:path` to print to stdout; a `slack:https://...` webhook URL posts directly instead) |

`--dry-parse` (`cloudcosttree <file> --dry-parse`) skips pricing entirely —
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

- This tool's own YAML/JSON schema (see `examples/aws-basic.yaml`) — the
  only format that can carry `resource_id`/`arn` by hand for `--with-usage`
  testing without a real Terraform state.
- Terraform (`.tf`, evaluated via a live `terraform plan` against whatever
  backend the config uses).
- A raw Terraform state file (`.tfstate`) — no `terraform` binary or live
  plan needed, since the state is already a snapshot of deployed values.
- A CloudFormation template (`--params` for parameter overrides).
- A CDK-synthesized template — run `cdk synth`, then point this tool at the
  result (`cdk.out/<StackName>.template.json`). No CDK-specific parsing
  exists or is needed: CDK emits standard CloudFormation, read through the
  exact same converter as a hand-written template — CDK's extra `Metadata`/
  `Transform`/`Outputs` keys and the synthetic `AWS::CDK::Metadata` resource
  it always injects are all handled already. See `examples/cdk-demo/`. One
  limitation carries over unchanged from plain CloudFormation: a property
  set via `Fn::GetAtt` (common in CDK's L2 constructs for cross-resource
  references, e.g. a security group ID from another construct) isn't
  resolved and reads as empty — the same as any other unresolved
  CloudFormation intrinsic (only a `{"Ref": "ParamName"}` against
  `--params`/`Parameters` is).
- A Pulumi stack export (`pulumi stack export`).
- A Terraform Cloud/Enterprise workspace's remote state, fetched live over
  the TFC/TFE API instead of a local file: `tfc://<org>/<workspace>` for
  app.terraform.io, or `tfe://<hostname>/<org>/<workspace>` for a
  self-hosted Terraform Enterprise install — pass either in place of a file
  path to `tree`/`analyze`/`diff`/`ci`/`history save`/`policy check`. Auth is
  a Terraform Cloud/Enterprise API token in the `TFE_TOKEN` environment
  variable — the same variable `terraform login` and the official `go-tfe`
  client already use, so a shell or CI job already configured for the
  `terraform` CLI needs no new secret. The workspace's current state version
  is fetched and priced exactly like a local `.tfstate` file — no new
  parsing, just a new byte source. See `pkg/parser/tfc.go`.
- A Terragrunt root directory — every unit's own plan is evaluated and the
  output is grouped by stack automatically (tree/diff/what-if/CSV all
  render one heading per Terragrunt unit); see `examples/terragrunt-demo/`.
- An Atmos (Cloud Posse) stack directory — a root containing
  `atmos.yaml`/`atmos.yml`, with per-stack YAML under `stacks/` declaring
  `components.terraform.<name>.vars` for one or more real Terraform
  component modules under `components/terraform/<name>/`. **Requires
  CloudCostTree Pro** — on Free, pointing this tool at an Atmos root exits
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
  one — 7 components spanning 12 distinct billable AWS resource types
  across 4 stacks (dev, staging, and two prod regions), with a real
  multi-level `import:` hierarchy (a per-tier sizing catalog shared across
  stacks, plus per-region mixins).

## Supported AWS resources

Priced natively (own `resource_hourly`/dimension entry, not a heuristic
fallback): EC2 instances (with root EBS volume, OS multiplier), RDS
instances and RDS Cluster/Aurora (Multi-AZ, provisioned IOPS, backup
retention, including separate Aurora writer/reader instances — Aurora
Serverless v2's `db.serverless` instance class is priced at an assumed 0.5
ACU floor, since its real min/max scaling range lives on a different
resource this tool can't cross-reference at analyze time), standalone
EBS volumes (gp2/gp3/io1/io2, provisioned IOPS and throughput, snapshots),
S3 buckets, EFS file systems, DynamoDB tables (provisioned RCU/WCU with
table-class multiplier, or on-demand), NAT Gateway (fixed rate + data
processed), Elastic IPs, ELB/ALB/NLB/GWLB, EKS clusters, ElastiCache
(single-node and Redis replication groups), VPN Gateway/Connection, Transit
Gateway VPC attachments, VPC Interface Endpoints, Redshift, Kinesis (Streams
and Firehose), ECS/Fargate services and task definitions, RDS Proxy, Lambda
(invocations + GB-seconds), CloudFront, CloudWatch (Logs ingestion, custom
metrics/alarms), API Gateway, GuardDuty, Security Hub, Config, CloudTrail,
SQS, SNS, Route 53 (hosted zone, health check, resolver endpoint), KMS,
Secrets Manager, MSK (Kafka), OpenSearch/Elasticsearch, DocumentDB and
Neptune (cluster instances only — the cluster resource itself has no
separate AWS charge), Network Firewall, WAFv2 Web ACL, FSx for Windows File
Server, AWS Lightsail (priced per bundle, General Purpose Linux bundles
only), DynamoDB Accelerator (DAX, priced per node type), AWS Managed
Microsoft AD, Amazon MQ (priced per broker instance type), AWS Backup
(vault storage), CloudHSM, Amazon SageMaker (classic notebook instances
only — real-time inference endpoints aren't priced, see below), AWS
Transfer Family, AWS Direct Connect (dedicated connections, priced per
bandwidth), Amazon ECR (repository storage), Amazon Managed Workflows for
Apache Airflow (MWAA, priced as the sum of an environment's
Environment/Scheduler/WebServer/Worker components), AWS Certificate
Manager Private CA (General-Purpose mode), FSx for Lustre/OpenZFS/NetApp
ONTAP (Persistent/Single-AZ SSD baseline — the Scratch deployment type
remains unmapped), Kinesis Data Analytics v2 (priced at the single-KPU
minimum every application runs at least, same "documented floor" posture as
Lambda/SQS/SNS below), AWS App Runner (priced at an assumed 1 vCPU/2GB
baseline configuration, same reasoning as ECS/Fargate below), Amazon
ECR Public (repository storage), AWS Systems Manager Parameter Store
(Advanced tier only — Standard and Intelligent-Tiering parameters under 4KB
are free, so they're deliberately left unmapped), Amazon Timestream for
InfluxDB (priced per DB instance type), Amazon Kendra (index base
capacity fee, Developer or Enterprise edition — the GenAI Enterprise
edition isn't mapped since Terraform doesn't yet expose it as an edition
value), Amazon EMR (master node + core instance fleet, each node priced
at its EC2 rate plus EMR's own per-instance-hour markup fee — task instance
groups and the instance-fleet configuration API aren't modeled, and a
multi-master HA config's master group is still priced as a single node),
Amazon MemoryDB for Redis/Valkey (priced per node type and engine, since
engine changes the price for the same node type), AWS Managed Blockchain
(peer node instance type — Terraform-only, since this tool's Cloud
Formation/Pulumi support couldn't confidently map a dedicated node
resource for it), Amazon GameLift (fleet EC2 instance type, billed under
GameLift's own service code rather than a markup on EC2 the way EMR's is),
Amazon Neptune Serverless (an assumed 1 NCU floor, same architecture as
Aurora Serverless v2 above), Amazon MSK Connect (a flat per-MCU-hour rate
times the connector's declared mcu_count x worker_count — only when
configured with fixed/provisioned capacity, not the autoscaling capacity
mode), Amazon DocumentDB Elastic Clusters (a flat per-vCPU-hour rate times
shard_capacity x shard_count; storage/backup aren't modeled), and Amazon
OpenSearch Serverless (an assumed 4 OCU floor — 2 indexing + 2 search,
AWS's own documented minimum for a standard collection — since a
collection has no capacity attribute of its own to read), AWS Database
Migration Service (replication instance type, Single-AZ rate regardless of
the resource's own multi_az setting), EC2 Capacity Reservations (priced at
the same rate as a normal running On-Demand instance of that type, times
instance_count — reuses the existing EC2 instance-type rates directly, no
dedicated fetched rate needed), AWS CodePipeline (a flat $1/month fee per
active pipeline), and Amazon Redshift Serverless (its base_capacity RPU
attribute — a real, already-declared value on the workgroup resource, so
unlike Aurora/Neptune Serverless above this needs no assumed floor at all
— times the real per-RPU rate), and Amazon OpenSearch Ingestion (a
pipeline's min_units, another real declared attribute needing no assumed
floor, times the same per-OCU rate as OpenSearch Serverless above —
confirmed identical across both services), and Amazon AppStream 2.0 (fleet
instance type x compute_capacity.desired_instances — priced at the
standard single-session Windows Fleet rate; Linux/multi-session/BYOL/
Elastic fleet configurations aren't fetched), and AWS Storage Gateway's FSx
File Gateway type only (`gateway_type = "FILE_FSX_SMB"`) — the only Storage
Gateway type with a fixed hourly fee of its own; S3 File Gateway, Volume
Gateway, and Tape Gateway genuinely have no fixed fee (billed purely for
underlying storage/data transfer), so those `gateway_type` values are
deliberately left unmapped rather than a gap. EC2 Dedicated Hosts are also
priced (per instance_family — a whole host is billed by family, not
individual instance size; hosts declared via the mutually exclusive
instance_type attribute instead aren't mapped, since the fetched rate has
no per-size breakdown to look them up against). Amazon Neptune Analytics
(a graph's provisioned_memory, in NCU — another real, already-declared
attribute needing no assumed floor, times a confirmed-flat $0.03/NCU-hr
rate). AWS MSK Serverless (a flat $0.75/hr per-cluster fee; ingress/egress/
storage/partition usage components aren't modeled). Amazon Q Business
(an index's edition — Starter or Enterprise — times its declared
capacity_configuration.units, another real attribute needing no assumed
floor). AWS Client VPN (a flat $0.10/hr per-endpoint fee; per-connection
usage isn't modeled). Standalone EBS snapshots (`aws_ebs_snapshot`'s
volume_size, a Computed attribute only known post-apply — reuses the
existing snapshot-size pricing this tool already had for RDS backups, no
new pricing wiring needed). AWS Lambda Provisioned Concurrency (an assumed
128MB baseline memory — the real memory_size lives on the
`aws_lambda_function` this config resource references, a cross-reference
this tool's per-resource parsers can't make — times the real
provisioned_concurrent_executions count). Amazon Bedrock Provisioned
Throughput (`aws_bedrock_provisioned_model_throughput`'s model_units — a
real, already-declared attribute needing no assumed floor, same pattern as
Redshift Serverless above — times a per-model-unit-hour rate). model_arn is
resolved against a hand-maintained model-ID lookup table (Terraform/Pulumi
only — no CloudFormation resource for this exists at all), since AWS's price
catalog indexes this by human-readable model name rather than the technical
model ID Terraform/Pulumi expose, and a Provisioned Throughput purchase
requires a context-window-qualified model ID (e.g.
`amazon.nova-lite-v1:0:300k`) that this tool strips back to the base model
before the lookup, since price doesn't vary by context window. Confirmed
region by region against AWS's own published list of
Provisioned-Throughput-eligible models and the real bulk offer file: Amazon's
own Nova/Titan models and Meta Llama 3.1/3.2 have a published rate, each
genuinely region-restricted (Nova/Titan mostly `us-east-1` and a handful of
others, Llama `us-west-2` only — a Llama resource still parses and resolves
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
limits to two existing cases, `aws_autoscaling_group`/`aws_sagemaker_endpoint`
below.

EC2 Auto Scaling groups (`aws_autoscaling_group`) are also priced — the
first of two resources this tool cross-references another declared
resource for (see `aws_sagemaker_endpoint` below for the second). An
ASG's own attributes never carry an instance_type: that lives entirely on
the separate `aws_launch_template`/`aws_launch_configuration` resource it
references (by real, post-apply ID for launch templates; by name for the
older launch configuration), so this parser does a single pre-pass over
every declared resource to resolve that reference before pricing — an
exception to this tool's otherwise strictly single-resource,
no-cross-referencing design (see the Aurora Serverless v2 gap above for
where that design is *not* bent). Falls back to `max_size`/`min_size` when
`desired_capacity` isn't set. An ASG using `mixed_instances_policy`
(multiple possible instance types with weighted overrides) isn't resolved
from declared config alone — there's no way to know which override
actually gets used without asking AWS directly, so it stays unpriced
(`autoscaling_group_unresolved`) unless `--with-usage` is used (see
[below](#usage-aware-finops---with-usage)) to resolve it from the group's
real, currently-running instances. CloudFormation and Pulumi support this cross-reference too: a CFN
template resolves the join by logical ID (via the `LaunchTemplate.
LaunchTemplateId`/`LaunchConfigurationName` property's `Ref`, since a
static template has no live stack to fetch a real post-apply ID from), and
a Pulumi stack export resolves it by the referenced resource's real,
already-deployed id/name (from its own `Outputs`) — same "post-apply ID"
join Terraform's `.tfstate` uses, just read from Pulumi's resource shape
instead.

EKS managed node groups (`aws_eks_node_group`) are priced too — unlike
ASGs, no cross-reference is needed here: `instance_types` and
`scaling_config` are declared directly on the node group resource itself.
Worker nodes are billed as plain EC2 instances (the EKS control plane's own
per-cluster fee is `eks_cluster`'s, fetched separately). Fargate-backed EKS
pods (`aws_eks_fargate_profile`/`AWS::EKS::FargateProfile`/
`aws:eks/fargateProfile:FargateProfile`) are priced too, at an assumed
Fargate baseline (0.25 vCPU/0.5 GB, the smallest Fargate task size, running
continuously) — a profile only selects which pods get scheduled onto
Fargate by namespace/label selector; the real per-pod vCPU/memory request
lives in the Kubernetes pod spec, a data source no format this tool parses
exposes. Reuses the exact same fetched rate as ECS/Fargate below (both
services bill the same underlying Fargate compute at the same per-vCPU/
per-GB price), not App Runner's different compute-unit rate.

`aws_sagemaker_endpoint` (real-time inference) is priced too, the second
and (by design) last cross-reference this tool's parsers make: its
`instance_type` lives on a separate
`aws_sagemaker_endpoint_configuration` resource, referenced by name via
`endpoint_config_name` — resolved by the same pre-pass-over-every-resource
pattern `aws_autoscaling_group` uses above. A multi-variant endpoint
configuration (`production_variants` with more than one entry, an A/B
test setup) is priced against its first declared variant only, since this
tool has no way to know real traffic split across variants. CloudFormation
and Pulumi support this cross-reference too, same join as the ASG one
above. Standalone Elastic IPs (`aws_eip`/`AWS::EC2::EIP`/
`aws:ec2/eip:Eip`) are also priced (public IPv4 addresses have billed the
same whether in use or not since Feb 2024, so an EIP resource is priced
identically regardless of association status).

One documented gap remains, deliberate:
- Amazon Managed Grafana isn't mapped at all: it's 100% per-user-month
  licensing with no fixed workspace-level fee to price (the same "no fixed
  capacity to represent" reasoning as Cognito/Step Functions/AppSync — see
  below).

`aws_globalaccelerator_accelerator` is mapped (visible in the tree, counted
in the resource total) but always prices at $0: AWS Global Accelerator's
flat per-accelerator hourly fee isn't exposed anywhere in the AWS Price
List API (confirmed against the real bulk offer file — every entry is a
region-pair data transfer dimension), so there's no way to fetch a real
number for it, unlike every other $0 case below which is just "not mapped
yet".

Any other AWS resource type — one this tool hasn't mapped a price for at
all — still shows up in the tree and counts toward the resource total,
priced $0 (indistinguishable from a resource that's genuinely free, like a
security group or a VPC, since neither has a resourceHourly entry to look
up). It never silently disappears from the report the way it used to for
CloudFormation/Pulumi templates before this existed.

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
- **x86 → Graviton (ARM64)** (t3→t4g, m5→m6g, c5→c6g, r5→r6g, EC2/RDS) —
  cheaper at the same size, but unlike every other repricing rule above
  this changes CPU architecture, so the message always asks you to confirm
  ARM64 compatibility (AMI/container base image, compiled dependencies)
  first — it's never framed as a free win. Quantified with a real $/mo
  figure on **Pro** when the catalog has a matching rate for that specific
  size (Graviton coverage in the published catalog is narrower than x86's —
  a size with no matching rate is silently skipped, same as any other
  repricing rule); Free sees an unquantified ~20-40% nudge instead. Not
  applied to ElastiCache — it's priced from a flat representative rate, not
  per instance type, so a family swap there would never change the number.
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
- **Non-production resource running 24/7** — an EC2/RDS/RDS Cluster
  resource tagged or named as dev/staging/test/qa/sandbox (an `Environment`-
  style tag, or a whole `-`/`_`/`.`-separated token of its name — not a raw
  substring match, so `latest-app` or `underdevelopment-svc` don't
  false-positive) with no autoscaling and still priced at the full default
  24/7 hours. Re-priced exactly at an assumed business-hours-only schedule
  (~173h/month, 40hr/week) via the same `HoursPerMonth` math
  `--hours-per-month` already uses, so the savings figure is real, not a
  flat percentage guess — available on **every plan**, since unlike the
  Reserved/Graviton rules above it needs no new pricing data asset, just
  logic over what's already declared. A resource that already has a reduced
  `HoursPerMonth` set (already scheduled) is never re-flagged.
- **Governance nudges** (no dollar figure): missing tags/generic resource
  names, Terraform's implicit `default_*` resources (default security
  group, VPC, route table, network ACL) left unmanaged, and an S3 bucket
  with no lifecycle/storage-class transition rule declared (checked both
  ways the AWS provider expresses one: the modern, separate
  `aws_s3_bucket_lifecycle_configuration` resource, or the older
  deprecated `lifecycle_rule` block on `aws_s3_bucket` itself — no dollar
  figure, since this tool has no way to know a bucket's real object
  count/size/access pattern). Shown standalone only when there's no real
  cost saving elsewhere (condensed, one line per issue), or always
  alongside cost recommendations with `--include-governance`.

Only shown when `--with-usage` (**Pro**) actually fetched real telemetry —
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

Available on **every plan** — no AWS account needed. Lambda, SQS, SNS, API
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

## Custom price books

```
cloudcosttree ./my-infra.tf --price-overrides discounts.yaml
```

Available on **every plan** — no AWS account, no hosted service. If your
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
given resource's type, changes nothing — the catalog's real on-demand rate
applies exactly as it always has.

This is deliberately an MVP: a flat percentage per service, not a model of
how a real EDP's discount can vary by purchase type (on-demand vs.
Reserved Instance vs. Savings Plan) — every discounted figure still starts
from a real, fetched AWS rate, this is just a multiplier applied on top of
it.

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
or an EC2/ECS/Lambda instance role — independent of any `profile` argument
on the input `.tf` file's own `provider "aws"` block, which only Terraform
itself reads; export `AWS_PROFILE=<name>` to point this flag at a named
profile) to replace static-config guesses with
real numbers (and confirm facts no static config can know at all, like an
EBS volume's real attachment status), for resources this tool can resolve a
real AWS resource ID for — a `.tfstate` file, a `terraform show -json` plan
against already-applied infrastructure, a `pulumi stack export`'s
per-resource `outputs.id`/`outputs.arn`, or a CloudFormation template paired
with `--stack-name <name>` (below). A brand-new resource being `create`d for
the first time (Terraform), or one Pulumi hasn't deployed yet (empty
`outputs`), has no real ID and is silently skipped for this enrichment (the
rest of the report is unaffected).

CloudFormation input is the one format that can't carry a real resource ID
itself at parse time — a plain template has no post-apply state of its own,
unlike the two deployment-aware formats above — so it needs one extra
opt-in step: `--stack-name <name>`, the name of the stack this template was
actually deployed as (`aws cloudformation create-stack --stack-name <name>
...`). With it, `--with-usage` makes one extra, read-only
`cloudformation:DescribeStackResources` call to resolve every resource's
real physical ID from its logical ID (matched the same way this tool's own
CloudFormation parser already keys resources by logical ID — see
`pkg/parser/cloudformation.go`), then every enrichment below runs exactly as
it would for a Terraform/Pulumi resource with a real ID. Without
`--stack-name`, CloudFormation input is skipped for `--with-usage` exactly
as before (a printed note, never a failure).

- **Real CPU-based right-sizing** — pulls each EC2/RDS/RDS Cluster
  resource's actual average CPU utilization from CloudWatch
  (`CPUUtilization`, 14-day lookback) and, when it's genuinely idle
  (under 10% average), recommends one size down within the same instance
  family/generation (e.g. `m5.xlarge` → `m5.large`) with an exact repriced
  dollar delta — instead of guessing anything from the declared instance
  type alone. Reserved-Instance-aware: also calls
  `ec2:DescribeReservedInstances` for every distinct EC2 instance type in
  your infrastructure, and when the account holds one or more active RIs of
  that exact type, the recommendation is caveated rather than silently
  suppressed — an RI existing doesn't confirm *this specific* instance is
  the one it covers (an account can run more instances of a type than it
  holds RIs for), so this tool never guesses either way. Stranding a paid
  RI commitment while paying on-demand for a smaller instance is often
  net-negative, which is exactly what the caveat asks you to check first.
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
- **Real `mixed_instances_policy` resolution** — another headline-number
  correction, not just a recommendation. An Auto Scaling Group using
  `mixed_instances_policy` has no single declared `instance_type` at all
  (multiple possible overrides, weighted) — declared config alone can't
  say which one actually got launched, so it renders unpriced
  (`autoscaling_group_unresolved`) without this. Calls
  `autoscaling:DescribeAutoScalingGroups` for every such ASG this tool can
  resolve a real ASG name for, which already reports each running
  instance's real `InstanceType` directly (no separate
  `ec2:DescribeInstances` call needed), and prices the group as the most
  common instance type among its currently `InService` instances — a
  mixed group can genuinely run more than one type at once, and this tool
  prices a resource as a single type × count, not a weighted mix.
- **Confirmed orphaned EBS volumes** — calls `ec2:DescribeVolumes` for every
  standalone EBS volume this tool can resolve a real volume ID for and flags
  the ones AWS confirms are genuinely unattached (`State: available`), at
  their full monthly cost. Deliberately not a static rule: a config-only
  check ("nothing in this file references this volume") would flag volumes
  that are actually attached via a separate Terraform root/module this tool
  never parsed, a false accusation this project's FinOps rules never make.
- **Confirmed orphaned EBS snapshots** — calls `ec2:DescribeSnapshots` for
  every standalone snapshot this tool can resolve a real snapshot ID for,
  then `ec2:DescribeVolumes` to confirm its source volume no longer
  exists, at the snapshot's full monthly cost. Same "AWS's own ground
  truth, not a config-only guess" discipline as the orphaned-volume check
  above.
- **Confirmed empty-target-group load balancers** — calls
  `elasticloadbalancing:DescribeTargetGroups` + `DescribeTargetHealth`
  for every ALB/NLB/GWLB this tool can resolve a real ARN for, and flags
  the ones with zero registered targets across every target group behind
  them, at the load balancer's full monthly cost. Classic ELB isn't
  covered (it predates ELBv2's target-group model entirely).
- **Confirmed unassociated Elastic IPs** — calls `ec2:DescribeAddresses`
  for every standalone EIP this tool can resolve a real allocation ID
  for, and flags the ones confirmed unassociated, at the address's full
  monthly cost — AWS bills a public IPv4 address the same whether it's
  attached to anything or not (since Feb 2024), so an unassociated one is
  pure waste, not "used to be free."
- **Lambda memory over-provisioning** — CloudWatch Metrics has no
  `MemoryUtilization` metric for Lambda at all (unlike EC2/RDS
  `CPUUtilization`), so this queries CloudWatch Logs Insights
  (`logs:StartQuery`/`GetQueryResults`) against every function's own
  `/aws/lambda/<name>` log group for the real average max-memory-used AWS
  writes to every invocation's `REPORT` log line — genuinely measured, not
  a metric this tool had to approximate. When that average sits well under
  the function's currently configured `memory_size`, recommends a smaller
  value (with headroom above what was actually measured) at an exact
  repriced dollar delta, disclosing the one real tradeoff it can't
  quantify: Lambda's CPU allocation scales with `memory_size`, so Duration
  should be re-checked after lowering it.
- **Fleet size outlier** — compares a plan's EC2/RDS resource against every
  other instance already running in that same AWS account/region
  (`ec2:DescribeInstances`/`rds:DescribeDBInstances`, grouped by instance
  family the same way `ruleOldGenerationInstance`/`ruleGravitonMigration`
  parse one), and flags it only when it's a genuine outlier against a real
  sample of at least 2 comparable instances: a different family than
  whichever one is most common in the fleet, or the largest size within a
  family it does share. No dollar figure — this tool has no way to know
  whether the new resource's size is a genuine business need, so it's a
  governance/consistency nudge, not a quantified saving, the same
  informational posture as `ruleEC2FleetWithoutASG`. Silent whenever there's
  no comparable fleet at all, or fewer than 2 other instances to compare
  against — this never guesses from a tiny sample. EC2 and RDS only for
  now; RDS Cluster/Aurora and ElastiCache aren't in scope yet.

### Multi-region and multi-account (`--accounts`)

Every call above is made once per distinct AWS region actually declared
across the infrastructure's resources (each resource's own `region` falling
back to the top-level one when unset), not just once for the whole run —
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
looks for `./accounts.yaml`, then `~/.cloudcosttree/accounts.yaml` — same
convention as `--policies`. `match` is matched against a Terraform
resource's own address when it has one (`module.prod.aws_instance.web`),
falling back to its plain name for every other input format. A resource
matching no entry — or when no `accounts.yaml` exists at all — uses the
default AWS credential chain, exactly as `--with-usage` always did; this is
purely additive. Needs `sts:AssumeRole` on the credentials running
`--with-usage`, plus a trust policy on each target `role_arn` allowing that
principal to assume it.

Needs `cloudwatch:GetMetricData`, `ec2:DescribeSpotPriceHistory`,
`ec2:DescribeVolumes`, `ec2:DescribeSnapshots`, `ec2:DescribeAddresses`,
`ec2:DescribeReservedInstances`, `ec2:DescribeInstances`,
`rds:DescribeDBInstances`,
`elasticloadbalancing:DescribeTargetGroups`/`DescribeTargetHealth`,
`logs:StartQuery`/`logs:GetQueryResults`,
`autoscaling:DescribeAutoScalingGroups`, and — with `--stack-name`,
CloudFormation input only — `cloudformation:DescribeStackResources` IAM
permissions. `ec2:DescribeInstances`/`rds:DescribeDBInstances` are the one
pair above that scan the whole account/region rather than looking up
specific resources by ID (every other call here targets IDs this tool
already resolved) — that's what the fleet size outlier check above needs to
see what else is already running. A
missing-credentials or missing-permission problem is
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

### Multi-resource scenarios (`--scenario`)

```
cloudcosttree analyze ./my-infra.tf --scenario changes.yaml
```

`--target`/per-resource flags simulate a change to exactly one resource.
`--scenario <path>` simulates changes to **several** resources in one run,
applied in file order against the same evolving infrastructure — the
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
accepted on the command line — nothing new to learn, just declared per
target instead of typed out as repeated `--target`/flag pairs (which the
CLI doesn't support directly: `--scenario` is the only way to change more
than one resource in a single what-if run). `--scenario` is mutually
exclusive with `-t`/`--target` and any individual what-if flag on the
command line — put every target's flags in the file instead.

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
`size_gb`, ...) — nothing new to learn there either. `type` and `name` are
required; `region` defaults to the infrastructure's own region if not given.
The synthesized resource has no `resource_id`/`arn` (nothing real exists yet
to have one) and renders ungrouped in the what-if tree (no module/stack
grouping) — acceptable for simulating "what if I add a read replica"-style
questions, where the point is the cost delta, not where it'd land in a real
module tree. `remove: true` (with a `target`) deletes that resource instead;
neither `add:` nor `remove:` can be combined with `flags:` in the same
entry. `--write-changes` doesn't support either yet — a scenario entry using
one is listed in `WHATIF_CHANGES.md` as unsupported, the same way an
unmapped flag or a non-literal expression already is.

### Writing simulated changes to disk (`--write-changes`, Pro)

```
cloudcosttree analyze ./my-infra.tf --target aws_instance.web --instance-type m5.large --write-changes ./out
```

`--write-changes <dir>` goes one step further than the console report or
`--export`: it writes the simulated change into a **new** directory —
your original input is never opened for writing. Only the specific
attribute(s) that changed are patched; everything else (formatting,
comments, unrelated resources) is left untouched. Works with `-t`/`--target`
or `--scenario`, the same way `--export` does.

Not every input format this tool reads can be written back to, and even
within a supported format, not every change can be:

- **Supported**: Terraform (`.tf`, including local modules) and Terragrunt
  — both are, underneath, a directory of HCL this tool copies and then
  patches in place, so `<dir>` must be a new, empty directory (Terraform
  evaluates the whole directory as one config, so there's no such thing as
  copying "just the one changed file") — plus this tool's own YAML/JSON
  schema, which is actually the *easiest* of the three: it has no
  variables or expressions at all, so there's no ambiguity about what's
  safe to overwrite, and (unlike Terraform/Terragrunt) it writes a single
  new file, `<name>_cct.<ext>`, next to the original — `<dir>` can be the
  same directory the input already lives in, and doesn't need to be empty,
  since the `_cct` suffix can never collide with a file you actually
  authored. Two caveats specific to this schema: the output is a fresh
  re-marshal of the fully-resolved result, not a byte-for-byte patch of
  your original file, so hand-written comments aren't preserved, and a
  field this tool normalizes automatically (e.g. a per-resource `region`,
  backfilled from the top-level one) may show up explicitly in the output
  even if you never wrote it yourself.
- **Not supported, structurally** — not "not yet": a raw `.tfstate` file, a
  `pulumi stack export`, and a CDK-synthesized template. None of these is
  code a person hand-edits and re-applies — they're deployed-state
  snapshots or build artifacts. A registry/remote Terraform module (a
  `module` block whose `source` isn't a local path) is out of scope for the
  same reason: there's no local file to patch.
- **Not supported yet, but plausible later**: a hand-written CloudFormation
  template (JSON/YAML, *not* CDK-synthesized output) is real source in
  principle, but needs its own intrinsics-aware patcher (`Ref`/`Fn::GetAtt`/
  `Fn::Sub` play the same "don't touch this" role `var.foo` plays for
  Terraform) — a separate implementation, not shipped yet.
- **Even in a supported format**: only a plain literal attribute is ever
  overwritten. An attribute set to a variable, a reference, or any other
  expression is left exactly as-is. Every change that couldn't be safely
  written — wrong format, non-literal, unmapped flag, ambiguous match — is
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
  change) rather than touching one line — every *other* key's value is
  still required to already be a plain literal too, or this declines the
  whole fallback rather than guess.

This is a **CloudCostTree Pro** feature — see [Free vs Pro](#free-vs-pro).
On Free, `--write-changes` is accepted but writes nothing: the report
renders exactly as it would without the flag, plus an explicit upgrade
note.

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
the default 6-policy template — same DSL, just different starting content:

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
to check every resource. `action` is `warn` \| `error` \| `deny` — the
latter two fail the run with a non-zero exit code, which is what CI/CD
gating builds on. `severity` (`critical`/`high`/`medium`/`low`) controls
display order and the icon shown in the violations section.

`scope` (optional) is `resource` (the default above) or `aggregate`. An
`aggregate`-scoped policy is checked exactly once against
whole-infrastructure facts instead of per-resource — `total_monthly_cost`
and `resource_count`, the only two plain fields the aggregate context
exposes — producing at most one violation with no single resource attached
to it. Mutually exclusive with `resource_type` (there's no single resource to
match a type against):

```yaml
- name: "Total infrastructure cost cap"
  scope: "aggregate"
  condition: "total_monthly_cost < 10000"
  action: "warn"
  severity: "high"
```

An aggregate condition can also use `count(<condition>)` — the one
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

`count(...)` is a special form, not a general function-call grammar — it's
only meaningful inside an aggregate condition (evaluating it in a
`resource`-scoped policy fails with an explicit error, rather than silently
returning 0).

Policy evaluation (cost guardrails, tag/FinOps rules) is a **CloudCostTree
Pro** feature — see [Free vs Pro](#free-vs-pro). On Free, `policy check`
requires an upgrade, and policy checks embedded in tree/analyze/diff/ci
silently evaluate zero policies (the cost report stays informational;
nothing can fail a build).

**`--max-monthly-cost <n>`** is a shortcut for exactly the aggregate cost
cap above, without writing a `policies.yaml` at all: `tree`/`analyze`/`diff`
and `ci report`/`check`/`diff` all accept it, folding a synthetic
`total_monthly_cost <= <n>` (`action: error`) policy into the same
evaluation as `--policies`, so it fails the run the same way any other
blocking policy does. Same **Pro** gate as every other policy check above —
unlike a `policies.yaml` violation, which just silently evaluates to
nothing on Free, passing `--max-monthly-cost` on Free prints an explicit
note that it wasn't enforced, so the flag never *looks* like it worked when
it didn't.

## Local apply guard (`guard`)

```
cloudcosttree guard -- terraform apply
```

Not the [CI/CD](#cicd) `Cost Guard` GitHub Actions workflow below — that
gates a pull request; this gates a real `terraform apply` on your own
machine, at the moment you'd actually run it, for the (common, for this
project's target audience) case where there's no CI/CD pipeline in the loop
at all yet. Run from the same directory you'd run `terraform apply` from:
`guard` runs `terraform plan` itself, checks that exact plan against your
policies, then applies that *same saved plan* — never a fresh one, so
nothing can drift between the check and the apply.

Default behavior is warn-only: a blocking policy violation (`action: error`
or `deny`) prints, but `terraform apply` still runs. `--block` opts into
actually gating it. This is deliberate — a plan-parsing edge case or a
false positive blocking a real infrastructure deploy is far more costly
than one appearing in a report, so blocking is opt-in, never the default:

```
cloudcosttree guard --block -- terraform apply
```

Same **CloudCostTree Pro** gate as `policy check` — `guard`'s only value is
policy enforcement, which is Pro-only on every other command too. The
wrapped command after `--` must be exactly `terraform apply`; this isn't a
generic subprocess wrapper.

## Cost Score

Every `tree`/`analyze`/`diff` run computes a **Cost Score** — a 0-100 number
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
Score is **available on every plan** — it's meant as a quick, shareable "is
this stack healthy" signal, not something gated behind an upgrade. It's
computed from each finding's *real* severity, not the Free-tier display
redaction some FinOps rules apply to their dollar figure (see
[FinOps recommendations](#finops-recommendations) above) — a real issue's
severity doesn't soften just because its exact $/mo figure is hidden from a
Free report.

It appears in every report format this tool produces: the console (`tree`/
`analyze`/`diff`), every `--export` format (`md`/`csv`/`json`/`html`/
`pr-comment`/`slack`), and — most usefully — `history save`/`list`/`compare`
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
cloudcosttree history list
cloudcosttree history compare <name-or-id> <name-or-id>
cloudcosttree history delete <name-or-id>
cloudcosttree history export <name> <path>
cloudcosttree history import <path>
```

Snapshots a cost tree locally (no account, no upload) so you can compare
cost — and [Cost Score](#cost-score) — over time the same way `diff`
compares two files. 180-day retention, auto-pruned — disk hygiene, not a
plan limit; identical on Free and Pro.

`history export`/`history import` copy that same snapshot JSON file to/from
an arbitrary path, so a snapshot can be shared with a team via git, S3, or
any storage already in use — no hosted backend needed. Not to be confused
with the `--export <format>[:path]` flag on `list`/`compare`/`save` below,
which renders a human-readable report instead of copying the raw snapshot.

### Cost delta attribution

`history compare` labels each changed resource's delta with a **cause**,
where it can tell — a $/mo swing between two snapshots doesn't always mean
your infrastructure changed:

```
Changed (1):
  ~ web [ec2] (price change)          +$4.80/month
```

- **`config change`** — the resource's instance type itself changed between
  snapshots.
- **`price change`** — the instance type is identical, but the AWS price
  catalog was refreshed between the two `history save` runs (this tool's
  published catalog updates on its own ~15-day cadence — see
  [Install](#install)) — the resource didn't change, its rate did.
- No label at all — the cause can't be determined (a snapshot saved before
  this attribution existed, or a real change this MVP doesn't fingerprint
  yet, like `size_gb`/`iops`). Never guessed; an unlabeled delta is exactly
  as informative as before this feature existed, nothing is silently
  misattributed.

When the catalog itself changed between the two snapshots being compared, a
note above the resource list calls that out explicitly, since it affects
how to read every `price change`-labeled line below it. This is a `config`
vs. `price` MVP, not full three-way attribution — declared-volume/usage
changes (a `--usage` file edit, or `--with-usage`'s real measured traffic)
aren't distinguished from a config change yet.

### Cost drift alerts in CI

`history compare` can fail the run (exit 1) when total cost *increased*
past a threshold — a decrease never blocks, this is a regression gate, not
a general change alert:

```sh
cloudcosttree history save "run-$CI_COMMIT_SHA" ./my-infra.tf
cloudcosttree history compare @previous @latest --fail-on-drift-pct 20
```

`@latest`/`@previous` resolve to the most, and second-most, recently saved
snapshot — so a CI job that saves one new snapshot per run never has to
track two names itself. `--fail-on-drift-pct <n>` and `--fail-on-drift-abs
<n>` are independent and can be combined: the percent check alone can't see
a brand-new, previously-untracked stack (0 → nonzero is a 0% delta, not a
percentage), so pair it with an absolute dollar threshold to catch that
case too. Works on both plans — this isn't a policy-engine check, just a
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
other format — handy for previewing the message before wiring it up for
real. `slack:<https://hooks.slack.com/services/...>` (anything starting
with `http://`/`https://`) instead **POSTs it directly** to that Slack
Incoming Webhook — no account, no OAuth app, nothing hosted by us in the
loop: the webhook URL is created entirely inside your own Slack workspace
and typically lives as a CI secret (`$SLACK_WEBHOOK_URL` above). Works
identically on every command that already supports `--export`
(`tree`/`analyze`/`diff`, `history save`/`list`/`compare`, `ci
report`/`check`/`diff`) — pair it with `history compare
--fail-on-drift-pct` (cost drift) or `ci check` (policy violations) to
turn an actionable event into a Slack message instead of a passive digest
nobody reads.

## CI/CD

See [CI.md](CI.md) for the full guide — GitHub Actions (a ready-to-use
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
a `license-key` input — no per-machine activation seat is spent doing this,
unlike the normal desktop `license activate` flow.

## VS Code extension

[vscode-extension/](vscode-extension/) adds an in-editor cost tree,
what-if panel, and diff view on top of the same CLI (every number comes
from a real `cloudcosttree analyze --export json:-` call, no re-implemented
pricing/parsing logic) — see its own README for setup.

The what-if panel mirrors both CLI what-if modes: "Apply What-If" previews
one resource's change (the `-t`/`--target` flow), and "＋ Add to Scenario"
(offered once a preview is showing) stages that same change alongside
others — "Run Scenario" then applies them all together in one combined
report, the UI equivalent of `--scenario`. Re-staging a resource already in
the list replaces its entry rather than duplicating it.

"Generate File (Pro)" materializes whichever what-if (single or scenario)
is currently showing as real file(s) via `--write-changes` — a new,
uniquely-named folder next to the original input, never the original
itself; see [What-if simulator](#what-if-simulator) for exactly which
input formats and attribute types this supports.

The `cloudcosttree.withUsage` setting is the extension's opt-in bridge to
[`--with-usage`](#usage-aware-finops---with-usage) (Pro) — turning it on
shows a one-time confirmation dialog (this is the one feature that calls
your own AWS account), then enriches Analyze/Compare the same way the CLI
flag does; see the extension's own README for the consent/credential
details.

## Free vs Pro

Free is a generous, unlimited cost-visibility tool for local use — Pro adds
CI/CD scale, the ability to actually enforce governance, real-dollar
Reserved Instance/Spot pricing, and usage-aware right-sizing.

| | Free | Pro ($14.99/mo) |
|---|---|---|
| Analyses (tree/analyze/diff) | Unlimited | Unlimited |
| What-if simulations | Unlimited | Unlimited |
| Exports (md/csv/json/html/pr-comment/slack) | Unlimited | Unlimited |
| History (`history save`/`list`/`compare`) | Unlimited, 180-day retention | Unlimited, 180-day retention |
| Cost Score (health grade rolling up FinOps + policy findings) | Included | Included |
| FinOps recommendations shown | Top 3 by impact | Top 15 by impact |
| Real usage volume for request/GB/event-billed resources (`--usage` file: Lambda, SQS, SNS, ...) | Included | Included |
| Real Reserved Instance $ savings | Unquantified nudge only | Real 1yr-no-upfront $/mo figure |
| Usage-aware FinOps (`--with-usage`: CloudWatch right-sizing + live Spot pricing + real Lambda cost correction) | Not included | Included |
| CI/CD runs (`ci report`/`check`/`diff`) | 1,000/month | Unlimited |
| Cost guardrails & tag/FinOps policies (`policy check`, and policy enforcement inside tree/analyze/diff/ci) | Not included — cost data stays informational | Unlimited, can fail a build on violation |
| Write simulated what-if changes to a new file/directory (`--write-changes`) | Not included | Included |
| Input format: Atmos (Cloud Posse) stacks | Not included | Included |
| Cloud provider support | AWS | AWS |
| VS Code extension | Included | Included |

History's 180-day retention (auto-pruned locally, see `pkg/history`) is disk
hygiene, not a plan limit — it's the same on both tiers. Custom/negotiated
[price books](#custom-price-books) (`--price-overrides`) are available on
both tiers too — a flat %-discount MVP, not a full purchase-type-aware
model.

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
pkg/usage/           --with-usage: live CloudWatch/EC2 Spot/EBS/EIP/ELBv2 calls (Pro)
pkg/finops/          Savings-recommendation rules (declared-config rules + usage-aware rules)
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
automation and fetched by end users as a plain public file — the only
CloudCostTree capability that needs an AWS account of its own is
`--with-usage`, and that account is always the end user's, never this
project's.

## License

Proprietary — all rights reserved. Not open source; no public
contribution/license grant is implied by this repository being readable.
