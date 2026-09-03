# CI/CD Integration

CloudCostTree has a dedicated `ci` command group built for pipelines instead
of a human terminal: JSON on stdout by default, a rich Markdown summary
published automatically wherever the pipeline supports it, GitHub Actions
annotations on policy violations, a 0/1/2 exit-code convention a build can
gate on, and a `comment` subcommand that posts (and updates in place, on
later runs) a real PR/MR comment on GitHub, GitLab, Azure Repos, or
Bitbucket directly from the binary, no separate `gh`/`curl`/`jq` script
required.

```
cloudcosttree ci report  <infrastructure_file>              # cost report only, never fails the build
cloudcosttree ci check   <infrastructure_file>               # cost report + policy checks, fails on violations
cloudcosttree ci diff    <baseline> <current>                 # same as check, comparing base branch vs. PR branch
cloudcosttree ci comment <platform> <infrastructure_file>     # same report, posted as a PR/MR comment
```

Run `cloudcosttree ci --help` (or `cloudcosttree ci comment --help`) for the
full flag reference. This document covers wiring these commands into GitHub
Actions, GitLab CI, Azure Pipelines, and Bitbucket Pipelines: GitLab,
Azure, and Bitbucket all post (and update in place, on later runs) a real
PR/MR comment via `ci comment`, not just log output, the same as the GitHub
Action does.

- [Quick start (GitHub Actions)](#quick-start-github-actions)
- [The `ci` command group](#the-ci-command-group)
- [GitHub Actions](#github-actions)
- [Using the CloudCostTree Action directly](#using-the-cloudcosttree-action-directly)
- [GitLab CI](#gitlab-ci)
- [Azure Pipelines](#azure-pipelines)
- [Bitbucket Pipelines](#bitbucket-pipelines)
- [Terraform Cloud / Atlantis](#terraform-cloud--atlantis)
- [Other CI systems](#other-ci-systems)
- [CI detection and colored output](#ci-detection-and-colored-output)
- [Installing CloudCostTree in a pipeline](#installing-cloudcosttree-in-a-pipeline)

## Quick start (GitHub Actions)

Both example workflows are thin wrappers around the reusable composite
action at the repo root ([`action.yml`](action.yml)): see
[Using the CloudCostTree Action directly](#using-the-cloudcosttree-action-directly)
if you'd rather reference it yourself than copy a whole workflow file.

Copy
[`cloudcosttree.yml`](https://github.com/rulssss/cloudcosttree/blob/main/.github/workflows/cloudcosttree.yml)
(cost visibility on every PR, never blocks a merge) and/or
[`cost-guard.yml`](https://github.com/rulssss/cloudcosttree/blob/main/.github/workflows/cost-guard.yml)
(policy enforcement that fails the build), both from the public
[`rulssss/cloudcosttree`](https://github.com/rulssss/cloudcosttree) repo,
already wired to `uses: rulssss/cloudcosttree@main` (downloads a prebuilt
binary; never touches CloudCostTree's private source), into your own
repository's `.github/workflows/`, then:

1. Edit the `INFRA_PATH`/`POLICIES_PATH` env vars near the top of each to
   point at your infrastructure files. That's the only required edit.
2. Optionally uncomment `license-key: ${{ secrets.CLOUDCOSTTREE_LICENSE_KEY }}`
   if you have a Pro license (after adding it as a repo secret): confirmed
   live on every run, no per-machine activation seat spent doing it (unlike
   `cloudcosttree license activate`). Leave it out to run as Free.

That's it: no marketplace listing required, no extra permissions beyond
what's already declared in the files, no signup, and (via the public action)
no source code exposed either way. Open a PR that touches infrastructure
and you'll get:

- a cost report + diff in the workflow run's **Summary** tab (GitHub's Step
  Summary, `cloudcosttree` writes it directly, nothing else to configure);
- inline warning/error annotations on the PR's "Files changed" tab for any
  policy violation, if you have a `policies.yaml` (see `cloudcosttree policy
  init`) **and** a CloudCostTree Pro license: cost guardrails and tag/FinOps
  policy evaluation are a Pro feature (see the root README's
  [Free vs Pro](README.md#free-vs-pro) table); on Free the report is
  cost-only and never has violations to annotate;
- a failed check, specifically for `cost-guard.yml`, if any violation is
  blocking (`action: error` or `action: deny`), Pro only, for the same
  reason.

Free-plan `ci report`/`ci check`/`ci diff`/`ci comment` calls also share a
1,000-runs-per-month quota across a repo's pipelines (`cloudcosttree license
status` shows current usage); Pro is unlimited. On GitHub Actions this is tracked
server-side, keyed by the repository: a plain local counter can't do this
job in CI, since every job runs on a fresh, disposable machine with nothing
to accumulate against.

## The `ci` command group

### `ci report`

```
cloudcosttree ci report <infrastructure_file> [-prices <path>] [-policies <path>] [-format json|md]
```

A cost report, nothing more: it never fails the build over what it finds
(a bad/unreadable input file is still a hard error, exit 1). Use it for
"show me the numbers on every PR" without gating anything.

### `ci check`

```
cloudcosttree ci check <infrastructure_file> [-prices <path>] [-policies <path>] [-format json|md]
```

Computes the cost report **and** evaluates your `policies.yaml` against it
(resolved the same way as the rest of the CLI: the `-policies` flag, then
`./policies.yaml`, then `~/.cloudcosttree/policies.yaml`; no policy file
found just means "nothing to check", not an error). Policy evaluation itself
requires a CloudCostTree Pro license: on Free, `ci check` still runs (and
still counts against the CI-run quota below) but always reports zero
violations, exit `0`. Its exit code is the gate:

| Exit code | Meaning                                              |
| --------- | ----------------------------------------------------- |
| `0`       | No policy violations.                                  |
| `1`       | Only non-blocking violations (policies with `action: warn`). |
| `2`       | At least one blocking violation (`action: error` or `action: deny`). |

### `ci diff`

```
cloudcosttree ci diff <baseline_file> <current_file> [-prices <path>] [-policies <path>] [-format json|md]
cloudcosttree ci diff <current_file> -baseline <baseline_file>
```

Same idea as `ci check`, but for two infrastructure snapshots: typically
the base branch (`baseline`) and the PR branch (`current`). Policies are
evaluated against `current` only (the state the PR is proposing), and the
report shows the cost delta between the two. The exit-code table above
applies identically.

### `ci comment`

```
cloudcosttree ci comment <github|gitlab|azure|bitbucket> <infrastructure_file> [options]
cloudcosttree ci comment <platform> <baseline_file> <current_file> [options]
cloudcosttree ci comment <platform> <current_file> -baseline <baseline_file> [options]
```

The same report+policy computation as `ci check` (one file) or `ci diff`
(two files / `-baseline`), posted directly as a PR/MR comment instead of
left for the pipeline script to publish itself: the built-in equivalent of
the curl/jq blocks earlier revisions of this document asked every
GitLab CI/Azure Pipelines/Bitbucket Pipelines job to hand-roll. GitHub
Actions jobs can use this too (handy on a self-hosted runner without `gh`
preinstalled), though the [quick-start Action](#quick-start-github-actions)
already posts via `gh pr comment` with nothing extra to configure.

Every flag needed to identify *which* PR/MR to comment on and how to
authenticate falls back to the environment variable that platform's CI
system already sets automatically: inside a real pipeline run, only
`-token` (and, on Azure, enabling **Allow scripts to access the OAuth
token** under the pipeline's Settings, same as the manual example further
down) ever needs wiring by hand:

| Flag | Platform | Falls back to |
| --- | --- | --- |
| `-token` | all | `$GITHUB_TOKEN` / `$GITLAB_TOKEN` / `$SYSTEM_ACCESSTOKEN` / `$BITBUCKET_STEP_OAUTH_TOKEN` |
| `-pull-request` | all | the PR/MR/thread ID from that platform's own CI environment (GitHub Actions' event payload, `$CI_MERGE_REQUEST_IID`, `$SYSTEM_PULLREQUEST_PULLREQUESTID`, `$BITBUCKET_PR_ID`) |
| `-github-repo` | GitHub | `$GITHUB_REPOSITORY` |
| `-gitlab-project`, `-gitlab-url` | GitLab | `$CI_PROJECT_ID`, `$CI_API_V4_URL` (else `https://gitlab.com/api/v4`) |
| `-azure-org-url`, `-azure-project`, `-azure-repo` | Azure | `$SYSTEM_COLLECTIONURI`, `$SYSTEM_TEAMPROJECT`, `$BUILD_REPOSITORY_NAME` |
| `-bitbucket-workspace`, `-bitbucket-repo` | Bitbucket | `$BITBUCKET_WORKSPACE`, `$BITBUCKET_REPO_SLUG` |

`-behavior` controls what happens when a previous CloudCostTree comment
(recognized by the same hidden `<!-- cloudcosttree-report -->` marker `ci
report`/`ci check`/`ci diff`'s Step Summary output uses) is already on the
PR/MR:

| Behavior | Effect |
| --- | --- |
| `update` (default) | Edit the existing comment in place, or create one if none exists yet; one CloudCostTree comment per PR/MR across every run. |
| `new` | Always post a fresh comment, leaving any previous one (and its now-stale numbers) untouched. |
| `delete-and-new` | Remove every previous CloudCostTree comment first, then post a new one: a fresh notification instead of a silent edit, without piling up history. |

Everything else (`-prices`/`-params`/`-policies`/`-max-monthly-cost`,
`-format` for the primary stdout result, `-export`, the Step Summary
write, and the exit-code convention) is identical to `ci check`/`ci diff`
above. A failure to reach the platform's API (bad token, network error) is
a hard error (exit `1`), separate from the policy-verdict exit codes.

### Outputs

All four commands, uniformly:

- **Stdout**: JSON by default: the exact same structured document
  `--export json` on the plain `tree`/`diff` commands produces, so anything
  that already parses that shape works here too. `ci check`/`ci diff`/`ci
  comment` wrap it in a small envelope:

  ```json
  {
    "status": "failure",
    "exit_code": 2,
    "report": { "...": "the full cost/violations report" }
  }
  ```

  Pass `-format md` to print a human-readable Markdown report instead
  (handy when running these commands locally rather than in a pipeline).

- **GitHub Step Summary**: whenever `$GITHUB_STEP_SUMMARY` is set (GitHub
  Actions sets it on every step automatically), a PR-comment-flavored
  Markdown report (collapsible tables and all) is appended there. This is
  a no-op, not an error, outside GitHub Actions.

- **GitHub Actions annotations**: `ci check`/`ci diff`/`ci comment` print one
  `::warning::`/`::error::` line per policy violation when
  `GITHUB_ACTIONS=true` (set automatically by every GitHub-hosted or
  self-hosted Actions runner): these render as inline markers on the PR's
  "Files changed" tab. They're written to stderr, so they never interfere
  with a `| jq` pipe reading stdout.

- **`-export <format>[:<path>]`**: additionally write the report in another
  format (`md`, `csv`, `json`, `html`, `pr-comment`, `slack`) to a file:
  same syntax as the plain `tree`/`analyze`/`diff` commands' `--export`.
  Always pass a `<path>` here: stdout is already used for the primary
  result. For `slack`, `<path>` can instead be a Slack Incoming Webhook URL
  (`slack:https://hooks.slack.com/services/...`): the report POSTs there
  directly instead of writing a file, handy for turning `ci check` policy
  violations into a Slack alert with no extra service in the loop:
  `cloudcosttree ci check ./my-infra.json -export slack:$SLACK_WEBHOOK_URL`.

## GitHub Actions

The two ready-to-use workflows in this repository, both built on the
composite action at the repo root ([`action.yml`](action.yml)):

- **[`.github/workflows/cloudcosttree.yml`](.github/workflows/cloudcosttree.yml)**:
  basic analysis. Checks out both the PR and base branch, calls the action
  with `baseline-path` set (so it runs `ci diff` under the hood), and posts
  the result to the Step Summary plus a PR comment via `gh pr comment`, no
  third-party action needed, `gh` is preinstalled on every GitHub-hosted
  runner. `fail-on-blocking: "false"` means this workflow never blocks a
  merge.

- **[`.github/workflows/cost-guard.yml`](.github/workflows/cost-guard.yml)**:
  policy enforcement. Calls the action with `mode: check`, which fails the
  job specifically on exit code `2` (blocking violations) while letting
  exit code `1` (warnings only) pass with a visible `::notice::`.

  Not the same thing as the CLI's own `cloudcosttree guard -- terraform
  apply` (see the main README's "Local apply guard" section): this
  workflow gates a pull request on GitHub Actions; `guard` gates a real
  `terraform apply` locally, at the moment you'd actually run it, for
  projects that don't have a CI/CD pipeline like this one in the loop yet.
  Same policy engine, two different trigger points.

### Using the CloudCostTree Action directly

Both workflows above are just a `uses:` call to the action at this repo's
root: reference it yourself if you want a custom workflow instead of
copying one of the examples:

```yaml
- uses: actions/checkout@v4

- name: CloudCostTree
  uses: rulssss/cloudcosttree@main
  with:
    infra-path: ./infra # required
    baseline-path: "" # optional, set it to run in "diff" mode
    policies-path: policies.yaml # optional, falls back like the CLI does
    mode: "" # "report" | "check" | "diff"; inferred from baseline-path if empty
    comment-on-pr: "true" # post/update a PR comment when on a pull_request event
    fail-on-blocking: "true" # fail the step on exit code 2 (blocking violations)
    license-key: ${{ secrets.CLOUDCOSTTREE_LICENSE_KEY }} # optional, Pro, omit to run as Free
```

Outputs: `exit-code` (0/1/2, same convention as `ci check`/`ci diff`) and
`violations-found` (`"true"`/`"false"`), so a downstream step can branch on
the result:

```yaml
- name: CloudCostTree
  id: cost
  uses: rulssss/cloudcosttree@main
  with:
    infra-path: ./infra

- if: steps.cost.outputs.violations-found == 'true'
  run: echo "Found something worth a second look."
```

Minimal inline example, if you'd rather not use the action at all and wire
the CLI up by hand:

```yaml
- name: Enforce cost & governance policies
  id: guard
  run: |
    set +e   # GitHub Actions runs steps with `bash -e`; we want the exit code, not an abort
    cloudcosttree ci check ./infra -policies policies.yaml
    echo "exit_code=$?" >> "$GITHUB_OUTPUT"

- name: Fail on blocking violations
  if: steps.guard.outputs.exit_code == '2'
  run: exit 1
```

That example only gates the build; it doesn't post anything. On a runner
without `gh` preinstalled (self-hosted runners aren't guaranteed to have
it, unlike GitHub-hosted ones), swap the `run:` step for [`ci comment
github`](#ci-comment) instead: it reads `$GITHUB_TOKEN` and the PR number
from the same environment GitHub Actions already sets, so only `env:
GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` needs adding:

```yaml
- name: Enforce cost & governance policies, post as a PR comment
  run: cloudcosttree ci comment github ./infra -policies policies.yaml
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## GitLab CI

GitLab sets `CI=true` and `GITLAB_CI=true` on every job automatically, so
`cloudcosttree` already detects it (colors off, structured output). There's
no GitLab equivalent of `$GITHUB_STEP_SUMMARY`, so publish the report as a
job artifact; for the merge request comment itself, use
[`ci comment gitlab`](#ci-comment): it already reads `$CI_PROJECT_ID`,
`$CI_MERGE_REQUEST_IID`, and `$CI_API_V4_URL` (all set automatically on a
merge-request pipeline), needing only a `$GITLAB_TOKEN` CI/CD variable
(a project access token with `api` scope, configured once) to authenticate.
It finds and updates CloudCostTree's own previous note on later runs
instead of piling up a new one every time: GitLab's plain REST API has no
built-in "edit my last comment" concept, so this is exactly the
find-by-hidden-marker-then-`PUT` logic a hand-written script would
otherwise need, just already built in.

```yaml
stages:
  - cost

variables:
  INFRA_PATH: infra
  POLICIES_PATH: policies.yaml
  CLOUDCOSTTREE_RELEASE: latest # or pin a tag, e.g. v0.1.3

cost-guard:
  stage: cost
  image: alpine:3.20
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
  before_script:
    - apk add --no-cache curl
    - |
      tag="$CLOUDCOSTTREE_RELEASE"
      if [ "$tag" = "latest" ]; then
        tag=$(curl -fsSL https://api.github.com/repos/rulssss/cloudcosttree/releases/latest | grep '"tag_name"' | cut -d '"' -f4)
      fi
      curl -fsSL "https://github.com/rulssss/cloudcosttree/releases/download/${tag}/cloudcosttree-linux-amd64" -o /usr/local/bin/cloudcosttree
      chmod +x /usr/local/bin/cloudcosttree
      curl -fsSL "https://github.com/rulssss/cloudcosttree/releases/download/${tag}/prices.json" -o prices.json
    # Optional, Pro: set CLOUDCOSTTREE_LICENSE_KEY as a masked CI/CD
    # variable to get Pro entitlement confirmed live on every run, no
    # per-machine activation seat spent doing it.
    #
    # Required for the merge request comment below: a project access token
    # with `api` scope, as a masked CI/CD variable named GITLAB_TOKEN.
  script:
    - cloudcosttree ci comment gitlab "$INFRA_PATH" -policies "$POLICIES_PATH" -prices prices.json > cost-report.json; echo "CT_EXIT=$?" >> ct.env
    - source ct.env
    - if [ "$CT_EXIT" = "2" ]; then echo "Blocking policy violations found."; exit 1; fi
    - if [ "$CT_EXIT" = "1" ]; then echo "Only non-blocking (warn) violations, not failing the pipeline."; fi
  artifacts:
    when: always
    paths:
      - cost-report.json
```

## Azure Pipelines

Azure Pipelines sets `TF_BUILD=True` on every run, which `cloudcosttree`
also detects. Use `##vso[task.logissue ...]` logging commands (Azure's
equivalent of GitHub's annotations) for the fail/warn notices below. Posting
the report as an actual PR comment (an Azure Repos "PR thread") needs the
pipeline's own OAuth token: enable **Allow scripts to access the OAuth
token** under this pipeline's Settings first (off by default). Azure
auto-populates env vars for most of what [`ci comment
azure`](#ci-comment) needs (`SYSTEM_COLLECTIONURI`, `SYSTEM_TEAMPROJECT`,
`BUILD_REPOSITORY_NAME`, `SYSTEM_PULLREQUEST_PULLREQUESTID`), but not the
OAuth token itself (`System.AccessToken` has no automatic env-var mapping)
, that one still needs mapping by hand, below. It finds and replies to
CloudCostTree's own previous thread on later runs instead of opening a new
one every time.

```yaml
trigger: none
pr:
  branches:
    include:
      - "*"

variables:
  INFRA_PATH: infra
  POLICIES_PATH: policies.yaml
  CLOUDCOSTTREE_RELEASE: latest # or pin a tag, e.g. v0.1.3

pool:
  vmImage: ubuntu-latest

steps:
  - script: |
      tag="$(CLOUDCOSTTREE_RELEASE)"
      if [ "$tag" = "latest" ]; then
        tag=$(curl -fsSL https://api.github.com/repos/rulssss/cloudcosttree/releases/latest | grep '"tag_name"' | cut -d '"' -f4)
      fi
      curl -fsSL "https://github.com/rulssss/cloudcosttree/releases/download/${tag}/cloudcosttree-linux-amd64" -o $(Agent.TempDirectory)/cloudcosttree
      chmod +x $(Agent.TempDirectory)/cloudcosttree
      curl -fsSL "https://github.com/rulssss/cloudcosttree/releases/download/${tag}/prices.json" -o $(Agent.TempDirectory)/prices.json
      echo "##vso[task.prependpath]$(Agent.TempDirectory)"
    displayName: "Install CloudCostTree"

  # Optional, Pro: set CLOUDCOSTTREE_LICENSE_KEY as a secret pipeline
  # variable to get Pro entitlement confirmed live on every run, no
  # per-machine activation seat spent doing it.
  - script: |
      set +e
      cloudcosttree ci comment azure $(INFRA_PATH) -policies $(POLICIES_PATH) -prices $(Agent.TempDirectory)/prices.json
      echo "##vso[task.setvariable variable=exitCode]$?"
    env:
      # System.AccessToken has no automatic env-var mapping (unlike the
      # System.CollectionUri/System.TeamProject/Build.Repository.Name/
      # System.PullRequest.PullRequestId variables ci comment reads on its
      # own), it only becomes usable once mapped explicitly here, and only
      # once "Allow scripts to access the OAuth token" is enabled above.
      SYSTEM_ACCESSTOKEN: $(System.AccessToken)
    displayName: "Enforce cost & governance policies, post as a PR comment"

  - script: |
      echo "##vso[task.logissue type=error]CloudCostTree found blocking policy violations."
      exit 1
    condition: eq(variables['exitCode'], '2')
    displayName: "Fail on blocking violations"

  - script: echo "##vso[task.logissue type=warning]CloudCostTree found only non-blocking (warn) policy violations."
    condition: eq(variables['exitCode'], '1')
    displayName: "Note non-blocking warnings"
```

On a non-PR build (no `System.PullRequest.PullRequestId`, e.g. a push to
main), `ci comment` fails outright with a "missing pull request" error
instead of silently skipping the comment step; add a `condition:
eq(variables['Build.Reason'], 'PullRequest')` on the "Enforce cost &
governance policies" step above if this pipeline also runs on non-PR
triggers.

## Bitbucket Pipelines

Bitbucket Pipelines sets `CI=true` on every run, which `cloudcosttree`
already detects. Unlike GitLab/Azure Pipelines above, posting a PR comment
here needs no separate token or pipeline setting at all: every Bitbucket
Pipelines run gets a repository-scoped OAuth token for free in
`$BITBUCKET_STEP_OAUTH_TOKEN`, which [`ci comment
bitbucket`](#ci-comment) already reads by default, good enough to comment
on the pull request that triggered the run. It finds and updates
CloudCostTree's own previous comment on later runs instead of adding a new
one every time.

```yaml
pipelines:
  pull-requests:
    "**":
      - step:
          name: Cost & policy check
          image: alpine:3.20
          script:
            - apk add --no-cache curl
            - |
              tag="latest"
              if [ "$tag" = "latest" ]; then
                tag=$(curl -fsSL https://api.github.com/repos/rulssss/cloudcosttree/releases/latest | grep '"tag_name"' | cut -d '"' -f4)
              fi
              curl -fsSL "https://github.com/rulssss/cloudcosttree/releases/download/${tag}/cloudcosttree-linux-amd64" -o /usr/local/bin/cloudcosttree
              chmod +x /usr/local/bin/cloudcosttree
              curl -fsSL "https://github.com/rulssss/cloudcosttree/releases/download/${tag}/prices.json" -o prices.json
            # Optional, Pro: set CLOUDCOSTTREE_LICENSE_KEY as a secured
            # repository variable to get Pro entitlement confirmed live on
            # every run, no per-machine activation seat spent doing it.
            - set +e
            - cloudcosttree ci comment bitbucket infra -policies policies.yaml -prices prices.json > cost-report.json
            - export CT_EXIT=$?
            - if [ "$CT_EXIT" = "2" ]; then echo "Blocking policy violations found."; exit 1; fi
            - if [ "$CT_EXIT" = "1" ]; then echo "Only non-blocking (warn) violations, not failing the pipeline."; fi
          artifacts:
            - cost-report.json
```

## Terraform Cloud / Atlantis

CloudCostTree's Terraform support has two paths: a `.tf` file/directory
triggers a live `terraform plan` this tool runs itself (needs the
`terraform` binary and backend credentials in the runner), while a raw
`.tfstate` file is parsed directly with **no** `terraform` binary needed at
all (see [Input formats](README.md#input-formats)). For a Terraform
Cloud/Atlantis-managed workspace, the state already lives remotely: the
practical way to check its cost in CI is to pull that state and feed it the
second path:

```sh
terraform state pull > terraform.tfstate
cloudcosttree ci check terraform.tfstate -policies policies.yaml
```

`terraform state pull` is a standard Terraform CLI command that works
against any configured remote backend (Terraform Cloud/Enterprise's own
backend, or Atlantis's, Atlantis itself just runs Terraform against
whatever backend the repo's config points at), and needs only the same
credentials a runner already has to talk to that backend, no separate
Terraform Cloud API token or Atlantis-specific integration required.

This reflects deployed infrastructure (the last successful apply), not an
in-flight plan: the right comparison point for `ci report`/`history save`
snapshots and `policy check` guardrails, though not a preview of a
not-yet-applied change the way `.tf`'s live-plan path is. Piping a
pre-generated `terraform show -json <planfile>` plan artifact (e.g. one
Atlantis already produced for its own PR comment) directly into
CloudCostTree isn't supported yet: only a live `.tf` plan or an
already-applied `.tfstate` are recognized input shapes today.

## Other CI systems

Jenkins, CircleCI, Buildkite, and anything else not covered above.
`cloudcosttree` already detects `JENKINS_URL`, `CIRCLECI`, and `BUILDKITE`
(see [CI detection and colored output](#ci-detection-and-colored-output)
below) alongside the generic `CI=true` convention nearly every CI system
sets, colors turn off and output stays clean automatically, no setup
needed for that part. There's no dedicated walkthrough for these three the
way there is for GitHub Actions/GitLab CI/Azure Pipelines/Bitbucket
Pipelines above, because the two things a platform-specific guide would
normally add are already covered generically:

- **Installing the binary**: identical everywhere; see [Installing
  CloudCostTree in a pipeline](#installing-cloudcosttree-in-a-pipeline)
  below. The same `curl`/`chmod` two-liner runs in a Jenkins agent, a
  CircleCI executor, or a Buildkite agent exactly as it does in the GitLab
  CI example above (Jenkins/CircleCI/Buildkite are all "bring your own
  shell script" platforms with no reusable-action equivalent, same as
  GitLab).
- **Gating the build**: `cloudcosttree ci check <path> -policies
  <path>` behaves identically regardless of what's invoking it: exit `0`
  clean, `1` warn-only, `2` blocking violations (see [`ci
  check`](#ci-check) above). Check `$?` after the command the same way the
  GitLab example does.

The one piece that's genuinely platform-specific is posting the result as
a PR/MR comment, and that's determined by **where your code is hosted**
(GitHub, GitLab, Bitbucket, ...), not by which CI system is running the
job. [`ci comment <platform>`](#ci-comment) already handles all four, so a
Jenkins job building a GitHub-hosted repo runs `cloudcosttree ci comment
github` with a `GITHUB_TOKEN` supplied as a Jenkins credential (mapped to
the `GITHUB_TOKEN` env var) instead of Actions' automatic one; a CircleCI
job building a GitLab-hosted repo runs `cloudcosttree ci comment gitlab`
the same way, with `$GITLAB_TOKEN`/`$CI_PROJECT_ID`/`$CI_MERGE_REQUEST_IID`
set as that CI system's own environment/context variables mirroring
GitLab's. Use whichever of the four `ci comment` platform names matches
your **git host**, not your CI system, and swap only the install/trigger
boilerplate for your platform's own syntax.

## CI detection and colored output

Every `cloudcosttree` command (not just `ci`) checks, at startup, whether
it looks like it's running in a pipeline:

- the generic `CI=true` convention (set by GitHub Actions, GitLab CI,
  Travis, Bitbucket Pipelines, and most others), or
- one of `GITHUB_ACTIONS`, `GITLAB_CI`, `TF_BUILD` (Azure Pipelines),
  `JENKINS_URL`, `CIRCLECI`, `BUILDKITE` being set, or
- the [`NO_COLOR`](https://no-color.org) convention (any non-empty value).

When any of those apply, ANSI color codes are omitted from every command's
output: raw escape codes only add noise to a log viewer that doesn't
render them, and structured output (JSON, annotations) is unaffected
either way.

## Installing CloudCostTree in a pipeline

CloudCostTree's main source repository is private (its licensing/pricing
logic isn't open source), so nothing above ever clones it; every example
downloads a prebuilt binary instead, published as GitHub Releases on the
public [`rulssss/cloudcosttree`](https://github.com/rulssss/cloudcosttree)
repository (linux/darwin/windows, amd64/arm64, alongside the price catalog
each release was built with).

- The **GitHub Action** does this for you automatically: see
  [action.yml](https://github.com/rulssss/cloudcosttree/blob/main/action.yml)
  in that repo for exactly how (`gh release download`, no `git clone`, no
  Go toolchain needed on the runner).
- The **GitLab CI / Azure Pipelines** examples above, which have no
  equivalent of a reusable action, do it explicitly with `curl`:

  ```sh
  curl -fsSL "https://github.com/rulssss/cloudcosttree/releases/latest/download/cloudcosttree-linux-amd64" -o cloudcosttree
  chmod +x cloudcosttree
  curl -fsSL "https://github.com/rulssss/cloudcosttree/releases/latest/download/prices.json" -o prices.json
  ```

  (the examples above resolve the "latest" tag explicitly first, since
  `.../releases/latest/download/...` redirects rather than being a stable
  URL some `curl` setups won't follow by default; see either example's
  `before_script`/install step for the exact one-liner.)

No PAT, no authentication, no Go toolchain on the runner at all: this was
the "once binary releases exist" future this section used to describe;
they exist now.
