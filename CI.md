# CI/CD Integration

CloudCostTree has a dedicated `ci` command group built for pipelines instead
of a human terminal: JSON on stdout by default, a rich Markdown summary
published automatically wherever the pipeline supports it, GitHub Actions
annotations on policy violations, and a 0/1/2 exit-code convention a build
can gate on.

```
cloudcosttree ci report <infrastructure_file>   # cost report only, never fails the build
cloudcosttree ci check  <infrastructure_file>   # cost report + policy checks, fails on violations
cloudcosttree ci diff   <baseline> <current>    # same as check, comparing base branch vs. PR branch
```

Run `cloudcosttree ci --help` for the full flag reference. This document
covers wiring those three commands into GitHub Actions, GitLab CI, and
Azure Pipelines.

- [Quick start (GitHub Actions)](#quick-start-github-actions)
- [The `ci` command group](#the-ci-command-group)
- [GitHub Actions](#github-actions)
- [Using the CloudCostTree Action directly](#using-the-cloudcosttree-action-directly)
- [GitLab CI](#gitlab-ci)
- [Azure Pipelines](#azure-pipelines)
- [CI detection and colored output](#ci-detection-and-colored-output)
- [Installing CloudCostTree in a pipeline](#installing-cloudcosttree-in-a-pipeline)

## Quick start (GitHub Actions)

Both example workflows are thin wrappers around the reusable composite
action at the repo root ([`action.yml`](action.yml)) — see
[Using the CloudCostTree Action directly](#using-the-cloudcosttree-action-directly)
if you'd rather reference it yourself than copy a whole workflow file.

Copy
[`cloudcosttree.yml`](https://github.com/rulssss/cloudcosttree/blob/main/.github/workflows/cloudcosttree.yml)
(cost visibility on every PR, never blocks a merge) and/or
[`cost-guard.yml`](https://github.com/rulssss/cloudcosttree/blob/main/.github/workflows/cost-guard.yml)
(policy enforcement that fails the build) — both from the public
[`rulssss/cloudcosttree`](https://github.com/rulssss/cloudcosttree) repo,
already wired to `uses: rulssss/cloudcosttree@main` (downloads a prebuilt
binary; never touches CloudCostTree's private source) — into your own
repository's `.github/workflows/`, then:

1. Edit the `INFRA_PATH`/`POLICIES_PATH` env vars near the top of each to
   point at your infrastructure files. That's the only required edit.
2. Optionally uncomment `license-key: ${{ secrets.CLOUDCOSTTREE_LICENSE_KEY }}`
   if you have a Pro license (after adding it as a repo secret) — confirmed
   live on every run, no per-machine activation seat spent doing it (unlike
   `cloudcosttree license activate`). Leave it out to run as Free.

(This repo's own copies of these two files, at
[`.github/workflows/cloudcosttree.yml`](.github/workflows/cloudcosttree.yml)
and [`.github/workflows/cost-guard.yml`](.github/workflows/cost-guard.yml),
use `uses: ./` / `uses: ./current` instead — that's this repo dogfooding its
own in-progress source, not something an external repo should copy.)

That's it — no marketplace listing required, no extra permissions beyond
what's already declared in the files, no signup, and (via the public action)
no source code exposed either way. Open a PR that touches infrastructure
and you'll get:

- a cost report + diff in the workflow run's **Summary** tab (GitHub's Step
  Summary — `cloudcosttree` writes it directly, nothing else to configure);
- inline warning/error annotations on the PR's "Files changed" tab for any
  policy violation, if you have a `policies.yaml` (see `cloudcosttree policy
  init`) **and** a CloudCostTree Pro license — cost guardrails and tag/FinOps
  policy evaluation are a Pro feature (see the root README's
  [Free vs Pro](README.md#free-vs-pro) table); on Free the report is
  cost-only and never has violations to annotate;
- a failed check, specifically for `cost-guard.yml`, if any violation is
  blocking (`action: error` or `action: deny`) — Pro only, for the same
  reason.

Free-plan `ci report`/`ci check`/`ci diff` calls also share a 1,000-runs-per-
month quota across a repo's pipelines (`cloudcosttree license status` shows
current usage); Pro is unlimited. On GitHub Actions this is tracked
server-side, keyed by the repository — a plain local counter can't do this
job in CI, since every job runs on a fresh, disposable machine with nothing
to accumulate against.

## The `ci` command group

### `ci report`

```
cloudcosttree ci report <infrastructure_file> [-prices <path>] [-policies <path>] [-format json|md]
```

A cost report, nothing more — it never fails the build over what it finds
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
requires a CloudCostTree Pro license — on Free, `ci check` still runs (and
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

Same idea as `ci check`, but for two infrastructure snapshots — typically
the base branch (`baseline`) and the PR branch (`current`). Policies are
evaluated against `current` only (the state the PR is proposing), and the
report shows the cost delta between the two. The exit-code table above
applies identically.

### Outputs

All three commands, uniformly:

- **Stdout**: JSON by default — the exact same structured document
  `--export json` on the plain `tree`/`diff` commands produces, so anything
  that already parses that shape works here too. `ci check`/`ci diff` wrap
  it in a small envelope:

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
  Markdown report — collapsible tables and all — is appended there. This is
  a no-op, not an error, outside GitHub Actions.

- **GitHub Actions annotations**: `ci check`/`ci diff` print one
  `::warning::`/`::error::` line per policy violation when
  `GITHUB_ACTIONS=true` (set automatically by every GitHub-hosted or
  self-hosted Actions runner) — these render as inline markers on the PR's
  "Files changed" tab. They're written to stderr, so they never interfere
  with a `| jq` pipe reading stdout.

- **`-export <format>[:<path>]`**: additionally write the report in another
  format (`md`, `csv`, `json`, `html`, `pr-comment`) to a file — same syntax
  as the plain `tree`/`analyze`/`diff` commands' `--export`. Always pass a
  `<path>` here: stdout is already used for the primary result.

## GitHub Actions

The two ready-to-use workflows in this repository, both built on the
composite action at the repo root ([`action.yml`](action.yml)):

- **[`.github/workflows/cloudcosttree.yml`](.github/workflows/cloudcosttree.yml)** —
  basic analysis. Checks out both the PR and base branch, calls the action
  with `baseline-path` set (so it runs `ci diff` under the hood), and posts
  the result to the Step Summary plus a PR comment via `gh pr comment` — no
  third-party action needed, `gh` is preinstalled on every GitHub-hosted
  runner. `fail-on-blocking: "false"` means this workflow never blocks a
  merge.

- **[`.github/workflows/cost-guard.yml`](.github/workflows/cost-guard.yml)** —
  policy enforcement. Calls the action with `mode: check`, which fails the
  job specifically on exit code `2` (blocking violations) while letting
  exit code `1` (warnings only) pass with a visible `::notice::`.

### Using the CloudCostTree Action directly

Both workflows above are just a `uses:` call to the action at this repo's
root — reference it yourself if you want a custom workflow instead of
copying one of the examples:

```yaml
- uses: actions/checkout@v4

- name: CloudCostTree
  uses: rulssss/cloudcosttree@main
  with:
    infra-path: ./infra # required
    baseline-path: "" # optional — set it to run in "diff" mode
    policies-path: policies.yaml # optional — falls back like the CLI does
    mode: "" # "report" | "check" | "diff"; inferred from baseline-path if empty
    comment-on-pr: "true" # post/update a PR comment when on a pull_request event
    fail-on-blocking: "true" # fail the step on exit code 2 (blocking violations)
    license-key: ${{ secrets.CLOUDCOSTTREE_LICENSE_KEY }} # optional, Pro — omit to run as Free
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

## GitLab CI

GitLab sets `CI=true` and `GITLAB_CI=true` on every job automatically, so
`cloudcosttree` already detects it (colors off, structured output). There's
no GitLab equivalent of `$GITHUB_STEP_SUMMARY`, so publish the report as a
job artifact and, optionally, post it as a merge request comment via
GitLab's REST API.

```yaml
stages:
  - cost

variables:
  INFRA_PATH: infra
  POLICIES_PATH: policies.yaml
  CLOUDCOSTTREE_RELEASE: latest # or pin a tag, e.g. v0.1.2

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
    # variable to get Pro entitlement confirmed live on every run — no
    # per-machine activation seat spent doing it.
  script:
    - cloudcosttree ci check "$INFRA_PATH" -policies "$POLICIES_PATH" -prices prices.json -export pr-comment:cost-report.md > cost-report.json; echo "CT_EXIT=$?" >> ct.env
    - cat cost-report.json
    - |
      # Post as a merge request comment (needs a project access token with
      # `api` scope in $GITLAB_TOKEN — a CI/CD variable you configure once).
      if [ -n "$GITLAB_TOKEN" ] && [ -n "$CI_MERGE_REQUEST_IID" ]; then
        curl --silent --request POST \
          --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
          --data-urlencode "body@cost-report.md" \
          "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/notes" \
          > /dev/null
      fi
    - source ct.env
    - if [ "$CT_EXIT" = "2" ]; then echo "Blocking policy violations found."; exit 1; fi
    - if [ "$CT_EXIT" = "1" ]; then echo "Only non-blocking (warn) violations — not failing the pipeline."; fi
  artifacts:
    when: always
    paths:
      - cost-report.json
      - cost-report.md
```

## Azure Pipelines

Azure Pipelines sets `TF_BUILD=True` on every run, which `cloudcosttree`
also detects. Use `##vso[task.logissue ...]` logging commands (Azure's
equivalent of GitHub's annotations) and `##vso[task.setvariable ...]` to
carry the exit code between steps.

```yaml
trigger: none
pr:
  branches:
    include:
      - "*"

variables:
  INFRA_PATH: infra
  POLICIES_PATH: policies.yaml
  CLOUDCOSTTREE_RELEASE: latest # or pin a tag, e.g. v0.1.2

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
  # variable to get Pro entitlement confirmed live on every run — no
  # per-machine activation seat spent doing it.
  - script: |
      set +e
      cloudcosttree ci check $(INFRA_PATH) -policies $(POLICIES_PATH) -prices $(Agent.TempDirectory)/prices.json
      echo "##vso[task.setvariable variable=exitCode]$?"
    displayName: "Enforce cost & governance policies"

  - script: |
      echo "##vso[task.logissue type=error]CloudCostTree found blocking policy violations."
      exit 1
    condition: eq(variables['exitCode'], '2')
    displayName: "Fail on blocking violations"

  - script: echo "##vso[task.logissue type=warning]CloudCostTree found only non-blocking (warn) policy violations."
    condition: eq(variables['exitCode'], '1')
    displayName: "Note non-blocking warnings"
```

## CI detection and colored output

Every `cloudcosttree` command (not just `ci`) checks, at startup, whether
it looks like it's running in a pipeline:

- the generic `CI=true` convention (set by GitHub Actions, GitLab CI,
  Travis, Bitbucket Pipelines, and most others), or
- one of `GITHUB_ACTIONS`, `GITLAB_CI`, `TF_BUILD` (Azure Pipelines),
  `JENKINS_URL`, `CIRCLECI`, `BUILDKITE` being set, or
- the [`NO_COLOR`](https://no-color.org) convention (any non-empty value).

When any of those apply, ANSI color codes are omitted from every command's
output — raw escape codes only add noise to a log viewer that doesn't
render them, and structured output (JSON, annotations) is unaffected
either way.

## Installing CloudCostTree in a pipeline

CloudCostTree's main source repository is private (its licensing/pricing
logic isn't open source), so nothing above ever clones it — every example
downloads a prebuilt binary instead, published as GitHub Releases on the
public [`rulssss/cloudcosttree`](https://github.com/rulssss/cloudcosttree)
repository (linux/darwin/windows, amd64/arm64, alongside the price catalog
each release was built with).

- The **GitHub Action** does this for you automatically — see
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
  URL some `curl` setups won't follow by default — see either example's
  `before_script`/install step for the exact one-liner.)

No PAT, no authentication, no Go toolchain on the runner at all — this was
the "once binary releases exist" future this section used to describe;
they exist now.
