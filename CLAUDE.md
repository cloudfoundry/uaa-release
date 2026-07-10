# CLAUDE.md — uaa-release

## System Overview

`uaa-release` is a **BOSH release** that packages and deploys [Cloud Foundry UAA](https://github.com/cloudfoundry/uaa) (the OAuth2/SSO identity provider for Cloud Foundry) as a set of VMs/jobs on a BOSH-managed platform. This repo does not contain UAA's application logic — that lives in the `src/uaa` git submodule (a separate Java/Spring Boot codebase) — it contains the **deployment glue**: ERB templates, packaging scripts, BOSH job/package specs, and Ruby/Go tests that turn the UAA WAR file into a runnable, configurable BOSH job. Architecturally this is a **BOSH release (packaging + deployment orchestration)** around a monolithic Java web application (Tomcat or embedded Spring Boot Tomcat), not a microservices system.

## Core Tech Stack & Tools

- **Deployment framework**: [BOSH](https://bosh.io) release format (`jobs/`, `packages/`, `spec` files, `.final_builds`/`.dev_builds`)
- **Application runtime** (packaged, not authored here): Java (BellSoft JDK, see `jdk-25.0.3/`), Apache Tomcat (`apache-tomcat-*.tar.gz`), Spring Boot (embedded Tomcat mode)
- **Templating**: ERB (`*.erb` files under `jobs/*/templates`) rendered by BOSH into job configs (`uaa.yml`, `bpm.yml`, `log4j2.properties`, `tomcat/server.xml`, etc.)
- **Config/process supervision**: [BPM](https://github.com/cloudfoundry/bpm-release) (`config/bpm.yml.erb`), Monit (`jobs/*/monit`)
- **Test frameworks**:
  - Ruby / RSpec (`bundle exec rake` or `rspec spec`) — validates ERB template rendering against fixture manifests (`spec/input/*.yml` → `spec/compare/*`)
  - Go / Ginkgo (`src/acceptance_tests`) — end-to-end acceptance tests run as a BOSH errand job against a live deployment
- **Dependency management**: Bundler (`Gemfile`/`Gemfile.lock`) for Ruby, Go modules (`go.mod`/`go.sum`) for acceptance tests, git submodule for `src/uaa`
- **CI**: GitHub Actions (`.github/`)
- **Backup/restore**: [BBR](https://github.com/cloudfoundry-incubator/bosh-backup-and-restore) scripts for the UAA database (`jobs/bbr-uaadb`)

## Repository Directory Structure

```
uaa-release/
├── jobs/                        # BOSH job definitions — one per deployable role
│   ├── uaa/                     # The UAA app itself
│   │   ├── spec                 # Job spec: properties, templates, provides/consumes links
│   │   ├── monit                # Process supervision config
│   │   └── templates/           # ERB templates rendered at deploy time
│   │       ├── bin/              #   start/stop/health-check/pre-start scripts
│   │       ├── config/           #   uaa.yml, bpm.yml, log4j2, tomcat server.xml, etc.
│   │       └── bbr/              #   backup/restore lock scripts
│   ├── bbr-uaadb/               # Errand job: backup/restore of the UAA database via BBR
│   └── acceptance-tests/        # Errand job: runs the Go/Ginkgo acceptance suite on-network
│       └── templates/run.erb    #   entrypoint invoked by `bosh run-errand`
├── packages/                    # BOSH packages — how binaries are compiled/assembled
│   ├── uaa/
│   │   ├── packaging            # Bash script: unpacks JDK + Tomcat, drops in the UAA WAR
│   │   └── spec                 # Declares source files (uaa/**/*, JDK tarball, Tomcat tarball)
│   └── acceptance-tests/        # Packaging for the Go acceptance test binary
├── src/
│   ├── uaa/                     # GIT SUBMODULE → github.com/cloudfoundry/uaa (Java/Spring app)
│   │                             #   UAA's actual application code lives here, NOT in this repo
│   └── acceptance_tests/        # Go source for the Ginkgo acceptance suite (not a submodule)
├── spec/                        # Ruby RSpec tests for this release's ERB templates
│   ├── *_spec.rb                #   e.g. uaa-release.erb_spec.rb, tomcat.server.xml.erb_spec.rb
│   ├── input/                   #   sample BOSH manifests used as spec fixtures
│   ├── compare/                 #   expected rendered output, diffed against actual render
│   └── support/                 #   custom matchers (e.g. yaml_eq)
├── config/                      # Release-level blob/final-version tracking (blobs.yml, final.yml)
├── scripts/                     # Dev workflow scripts: create-dev-release, run-locally, test-runner, etc.
├── bin/                         # CI/release helper scripts (build/deploy, show version, licenses)
├── docs/                        # Legacy bosh-micro-cli era docs
├── releases/uaa/                # Finalized release manifests (*.yml) tracked per version
├── .dev_builds/ , .final_builds/# BOSH-managed blob storage for compiled dev/final releases
├── Rakefile, Gemfile             # Ruby test runner entrypoint (`rake` → runs spec/**/*_spec.rb)
└── manifest*.yml, opsfile.yml    # Example/working BOSH deployment manifests + an ops-file
```

## Key Architecture & Data Flow

**Build/package time** (`bosh create-release` / CI):
`packages/uaa/spec` (declares inputs: `src/uaa` submodule output, JDK tarball, Tomcat tarball) → `packages/uaa/packaging` (bash script compiles/assembles: unpacks JDK, unpacks Tomcat, copies in `cloudfoundry-identity-uaa.war` as `ROOT.war`, copies the statsd WAR and Tomcat listener jar) → a versioned, immutable **compiled package** blob.

**Deploy time** (`bosh deploy`):
Operator-supplied BOSH manifest properties → `jobs/uaa/spec` (declares/validates properties, and BOSH links like `uaa_db`, `uaa_keys`, `router`, `database`) → ERB templates under `jobs/uaa/templates/` are rendered with those properties → produces `config/uaa.yml`, `config/bpm.yml`, `config/tomcat/server.xml`, `config/log4j2.properties`, `bin/pre-start`, `bin/health_check`, etc. on the target VM → **Monit** starts the job via **BPM**, which launches either Tomcat (WAR deployment, `runtime.tomcat.enabled=true`) or the embedded Spring Boot runtime → the running UAA app talks to the UAA database (via the `uaa_db`/`database` BOSH link) and optionally an LDAP/SAML IdP per configured properties.

**Errand jobs** run on-demand via `bosh run-errand`:
- `acceptance-tests` — deployed alongside UAA on the same network, shells out to `bosh ssh`/`bosh scp` and makes HTTP calls directly to the UAA instance (deliberately avoids jumpboxes, per the comment in `jobs/acceptance-tests/spec`).
- `bbr-uaadb` — invoked by BOSH Backup and Restore to lock/dump/restore the UAA database.

**Verification loop** (this repo's own tests, not UAA's): RSpec renders each ERB template against fixture manifests in `spec/input/*.yml` and diffs the output against golden files in `spec/compare/*`, catching template regressions before a real deploy.

## Development Setup & Crucial Commands

**Requirements**: Ruby + Bundler (template tests), Go (acceptance tests), a BOSH director + `bosh` CLI (real deploys), git submodules initialized (`src/uaa`).

| Task | Command |
|---|---|
| Clone with submodules | `git clone --recursive <repo>` or `git submodule update --init` |
| Install Ruby deps | `bundle install` |
| Run all template specs | `bundle exec rake` (or `bundle exec rspec spec`) |
| Run a single template spec | `bundle exec rspec spec/uaa-release.erb_spec.rb` |
| Run Ruby template tests (explicit) | `scripts/run-template-tests.rb` |
| Shellcheck the release's scripts | `scripts/shellcheck.sh` |
| Create a dev release (local blob) | `scripts/create-dev-release.sh` |
| Deploy locally against bosh-lite/local director | `scripts/run-locally.sh` |
| Run acceptance tests locally (Docker) | `./scripts/run-locally.sh` then `go run github.com/onsi/ginkgo/ginkgo -v --progress --trace -r .` inside `src/acceptance_tests` (see `src/acceptance_tests/README.md`; do **not** use Docker for Mac — it's broken for this flow) |
| Run acceptance tests via BOSH errand | `bosh run-errand acceptance-tests` |
| Perform an official release | `scripts/perform-release.sh` |
| Refresh a local uaa-release deployment | `scripts/refresh-uaa-deployment.sh` |
| Tear down local BOSH env | `scripts/teardown-local.sh` |

## Guardrails & Design Patterns

- **Never edit UAA application code in this repo.** `src/uaa` is a pinned git submodule tracking `github.com/cloudfoundry/uaa`. Application/business-logic changes belong in that upstream repo and land here only as a submodule SHA bump (see recent commit history: `Bump UAA to <sha>`). This repo owns *packaging and deployment*, not app behavior.
- **Every property exposed to operators must be declared in the job `spec` file** (`jobs/uaa/spec`, `jobs/bbr-uaadb/spec`, `jobs/acceptance-tests/spec`) before it can be referenced in an ERB template — BOSH validates templates against the spec's `properties:` block.
- **Template changes require a corresponding RSpec fixture/golden-file update.** Any change to a file under `jobs/*/templates` should have a matching case in `spec/*_spec.rb`, an input manifest in `spec/input/`, and expected output in `spec/compare/`. Run `bundle exec rake` before considering a template change done.
- **Deprecated properties must keep working.** See `spec/input/deprecated-properties-still-work.yml` — this release maintains backward compatibility for renamed/deprecated manifest properties rather than breaking existing deployments.
- **Packaging scripts (`packages/*/packaging`) run with `set -e -x`** — treat them as fail-fast; don't suppress errors, and any added step should preserve strict-mode safety (check exit codes explicitly where subshells are involved, as the existing JDK/Tomcat unpack steps do).
- **Errand jobs run on-network deliberately.** The `acceptance-tests` job's placement is a documented workaround (see comment block in `jobs/acceptance-tests/spec`) for jumpbox/SOCKS5 timeouts and read-only `/etc/hosts` on Concourse workers — don't "simplify" this back onto an off-network worker without re-reading that rationale.
- **Two build stages exist for blobs**: `.dev_builds/` (local, iterative) vs `.final_builds/` (official, versioned) — tracked via `config/blobs.yml`/`config/final.yml`. Don't hand-edit blob directories; use the `scripts/`/`bosh create-release --final` flow.
- **Repo-root scratch/diagnostic files are not part of the release.** Files like `check-*.sh`, `find-*.sh`, `*-diagnostics.md`, `tomcat-troubleshooting-guide.md`, `manifest-*.yml` variants, and the `apache-tomcat-*.tar.gz`/`jdk-25.0.3/` directories at repo root are local working/debug artifacts, not tracked release inputs — the canonical manifest inputs are `manifest.yml`/`opsfile.yml` and the `jobs/`/`packages/` specs.
