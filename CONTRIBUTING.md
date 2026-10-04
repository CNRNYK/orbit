# Contributing to Orbit

Orbit is an early-access macOS app. Small, focused contributions and reproducible bug reports are welcome once repository access is available.

For bugs, include Orbit/macOS versions, architecture, steps and expected/actual behavior. Redact logs and screenshots. Feature requests should explain the problem and proposed flow. Do not post suspected vulnerabilities publicly; read [SECURITY.md](SECURITY.md).

Use a feature branch and pull request. Describe the resulting behavior and verification. For implementation changes, run `bash test.sh` and `bash build.sh`, plus relevant UI or installed-device checks. Documentation-only changes need link and format checks. Do not test against real apps, user profiles, login settings or private recordings without authorization.

Preserve reviewed operations, exact filesystem scope, independent installation/removal choices, optional permission consent, and local capture storage. Avoid turning transitive Homebrew dependencies into direct setup entries.

Start with [architecture](docs/ARCHITECTURE.md), [AI-assisted development](docs/AI-DEVELOPMENT.md), [testing](docs/TESTING.md) and [release guidance](docs/RELEASING.md). Source contributions use the [MIT license](LICENSE); third-party assets retain their owners' terms.
