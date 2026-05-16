# Deploying the site

The docs site and all three Flutter example apps are bundled into a single
Cloudflare Pages project (`plugin-kit`) and served under one domain:

| Path | Source | Built with |
| --- | --- | --- |
| `https://plugin-kit.saad-ardati.dev/` | `website/` (Astro + Starlight) | `pnpm --filter ./website build` |
| `https://plugin-kit.saad-ardati.dev/code-editor` | `example/code_editor` | `flutter build web --release --no-tree-shake-icons --base-href=/code-editor/` |
| `https://plugin-kit.saad-ardati.dev/dialog` | `example/plugin_kit_dialog_demo` | `flutter build web --release --base-href=/dialog/` |
| `https://plugin-kit.saad-ardati.dev/state-garden` | `example/state_garden` | `flutter build web --release --base-href=/state-garden/` |

Every push to `main` rebuilds all four and ships them in one
`wrangler pages deploy`. Same-repo pull requests get a preview deploy at
`<hash>.plugin-kit.pages.dev`; fork PRs run the build as a check but skip the
deploy step (no secrets).

The workflow lives at `.github/workflows/deploy-site.yml`.

## How the bundling works

The Flutter examples are built with `--base-href=/<sub>/`, which substitutes
the `<base href>` tag in each app's `web/index.html`. That makes the apps
load assets relative to their sub-path (`/dialog/main.dart.js`,
`/dialog/canvaskit/...`, etc.) instead of `/`. After the Astro build emits
`website/dist/`, the workflow copies each Flutter `build/web/` into
`website/dist/<sub>/`, then deploys `website/dist` as one unit.

## One-time Cloudflare setup

1. Create a single Pages project named `plugin-kit` in the Cloudflare
   dashboard. Use **Direct Upload** (not the Git integration) since GitHub
   Actions does the build and ships the bundle via wrangler.
2. Add the custom domain `plugin-kit.saad-ardati.dev` to the project.
   Cloudflare auto-issues the TLS cert. If `saad-ardati.dev` is on
   Cloudflare nameservers, the DNS record is created for you; otherwise
   add a CNAME at the registrar pointing the subdomain at the project's
   `plugin-kit.pages.dev` hostname.
3. Mint a Cloudflare API token with the `Cloudflare Pages: Edit`
   permission. Scope it to the account that owns the project.
4. Find your Cloudflare account ID in the dashboard sidebar.

## One-time GitHub setup

Add two repository secrets at
`https://github.com/SaadArdati/plugin_kit/settings/secrets/actions`:

- `CLOUDFLARE_API_TOKEN`: the token from step 3 above.
- `CLOUDFLARE_ACCOUNT_ID`: the account ID from step 4 above.

## Build details

- Flutter channel: `stable`, cached by `subosito/flutter-action@v2`.
- Node 22 + pnpm 9 for the Astro build.
- `code_editor` builds with `--no-tree-shake-icons` because it constructs
  `IconData` non-constantly; tree-shaking refuses to run in that case.
- `pub get` is run once at the workspace root, since the repo is a Flutter
  workspace and resolution happens there.
- `pnpm install` uses `--frozen-lockfile` so `website/pnpm-lock.yaml` is
  authoritative; refresh locally with `pnpm --filter ./website install` and
  commit the lockfile when transitive deps drift.

## Adding another sub-path

1. If it's a Flutter example, ensure web platform support
   (`flutter create --platforms=web .`) and a clean
   `flutter build web --release` locally.
2. Add a build step in `deploy-site.yml` with `--base-href=/<sub>/` matching
   the path you want.
3. Add a copy step under "Combine into single dist" to drop the build into
   `website/dist/<sub>/`.
4. Update the table at the top of this file.
