# Deploying the example apps

The three Flutter example apps under `example/` are auto-deployed to Cloudflare
Pages on every push to `main`. Pull requests get a preview deploy on the same
project, addressable via the PR's branch URL.

| Example | Cloudflare project | Source dir |
| --- | --- | --- |
| Code editor | `plugin-kit-code-editor` | `example/code_editor` |
| Plugin Kit dialog demo | `plugin-kit-dialog-demo` | `example/plugin_kit_dialog_demo` |
| State Garden | `plugin-kit-state-garden` | `example/state_garden` |

The workflow lives at `.github/workflows/deploy-examples.yml`. It runs one job
per example via a matrix, caches the Flutter SDK, builds web in release mode,
and ships the `build/web` directory through `wrangler pages deploy`.

## One-time Cloudflare setup

1. Create three Pages projects in the Cloudflare dashboard. Each one uses
   "Direct Upload" (not the Git integration), since GitHub Actions does the
   build and upload. Names must match the table above exactly.
2. Mint a Cloudflare API token with the `Cloudflare Pages: Edit` permission.
   Scope it to the account that owns the projects.
3. Find your Cloudflare account ID in the dashboard sidebar.

## One-time GitHub setup

Add two repository secrets at
`https://github.com/SaadArdati/plugin_kit/settings/secrets/actions`:

- `CLOUDFLARE_API_TOKEN`: the token from step 2 above.
- `CLOUDFLARE_ACCOUNT_ID`: the account ID from step 3 above.

## Build details

- Flutter channel: `stable`, cached by `subosito/flutter-action@v2`.
- `code_editor` builds with `--no-tree-shake-icons` because it constructs
  `IconData` non-constantly; tree-shaking refuses to run in that case.
- `pub get` is run once at the workspace root, since the repo is a Flutter
  workspace and resolution happens there.

## Adding another example

1. Make sure the example has `flutter` as an SDK dependency and a `web/`
   folder (run `flutter create --platforms=web .` inside it).
2. Confirm `flutter build web --release` succeeds locally.
3. Create a new Pages project in the Cloudflare dashboard.
4. Add a row to the `matrix.example` list in `deploy-examples.yml` with the
   directory, the project name, and any extra build args (e.g.
   `--no-tree-shake-icons` if needed).
5. Update the table at the top of this file.
