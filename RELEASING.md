# Releasing the CloudCostTree GitHub Action

The composite action at the repo root ([`action.yml`](action.yml)) is published
to the [GitHub Marketplace](https://github.com/marketplace/actions/cloudcosttree).

It is versioned **independently of the `cloudcosttree` CLI binary releases**.
The CLI binaries use the `v0.x` tag line in this same repo (cut automatically by
the private `release.yml`); the action uses its own `v1.x` line. The private
`release.yml` "Determine version" step is pinned to the latest `v0.*` release so
the two lines never collide — do not remove that pin.

## Tag scheme

| Tag                                              | Meaning                                              | Who pins it                                        |
| ------------------------------------------------ | --------------------------------------------------- | ------------------------------------------------- |
| `vX.Y.Z` — annotated, never moved                | one exact action release                             | reproducible builds                               |
| `vX` — lightweight, **moved forward** on every compatible `vX.Y.Z` | latest compatible release in major `X`               | most users: `uses: rulssss/cloudcosttree@v1`      |
| `main`                                            | development tip                                      | `uses: rulssss/cloudcosttree@main`               |

`MINOR` bump for new inputs/outputs or behaviour that stays backward compatible;
`PATCH` for fixes. A breaking change means a new major: cut `v2.0.0`, start a
`v2` tag, and update every doc/example that currently says `@v1`.

## Cutting a new action release

Run on `main`, after the `action.yml` change is merged and verified:

```sh
NEW=v1.0.1   # bump from the current latest v1.x tag

# 1. immutable release tag
git tag -a "$NEW" -m "CloudCostTree Action $NEW"
git push origin "$NEW"

# 2. move the major tag forward
git tag -f v1 "$NEW"
git push -f origin v1
```

Then on github.com:

1. **Releases → Draft a new release**, pick the tag `$NEW`.
2. Title `CloudCostTree Action $NEW`; body = what changed + the `uses:` snippet.
3. Tick **Publish this Action to the GitHub Marketplace**.
4. Keep the categories (Primary **Continuous integration**, Secondary
   **Utilities**).
5. Confirm the auto-checks show "Everything looks good", then **Publish release**.

The first-ever release (`v1.0.0`) additionally asks you to accept the GitHub
Marketplace Developer Agreement; later releases don't.

## Never

- Do **not** run the private `release.yml` with `delete_others: true` while a
  `v1.x` Marketplace release exists — it deletes every other release, including
  the one backing the Marketplace listing.
- Do **not** hand-cut a `v0.x` tag here; those are the CLI's, managed by
  `release.yml`.
