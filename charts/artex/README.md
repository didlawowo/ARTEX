# artex

Helm chart for [ARTEX](https://github.com/BaaRai/ARTEX): an AI autonomous
penetration-testing platform (web console, exploration engine, recording proxy,
report generation) backed by PostgreSQL.

The chart deploys the application only. PostgreSQL is an external dependency,
reachable from the pod.

```bash
helm install artex oci://ghcr.io/didlawowo/charts/artex \
  --namespace artex --create-namespace \
  --set database.host=postgres.database.svc \
  --set database.password='<postgres-password>' \
  --set llm.anthropicApiKey='<key>'
```

Then read the one-time setup token and open `/setup`:

```bash
kubectl -n artex logs deploy/artex | grep -i "setup token"
```

## Deployment notes

These four points explain most of the chart's shape. Read them before overriding
defaults.

**The server runs as root on purpose.** The only configuration where ARTEX
isolates the processes its agent starts (Bash, custom tools, MCP servers) is a
root server that drops each child to `executor.uid` (10001 by default). Running
the container as a non-root user silently disables that isolation: the agent then
keeps the server identity. The chart therefore sets `runAsUser: 0` and
`runAsNonRoot: false`, and `allowPrivilegeEscalation: false` (which sets
`no_new_privs`) stays compatible because dropping privileges is not an
escalation.

**Do not drop capabilities.** The container runtime defaults include `SETUID`,
`SETGID` (needed for the privilege drop) and `NET_RAW` (needed by `nmap` SYN
scans). Dropping `ALL` breaks both, and the executor drop fails closed at
startup.

**The recording proxy port (8788) is not published.** The Service exposes only
the console port (8787). Port 8788 is a MITM proxy for the agent's own traffic
capture; exposing it through a Service would offer a proxy to every pod in the
cluster.

**State lives on two volumes.** `keys/` holds `jwt.key` (session signing) and
`secret.key` (AES-256-GCM key for credential-bearing columns). Losing it signs
every operator out and makes encrypted rows unreadable, so keep it on a
persistent claim and include it in backups. `data/` holds the traffic index, task
files, transcripts and archives.

## TLS and reverse proxies

There is no TLS in the pod. The session token travels in a cookie and can also be
passed as a query parameter, so terminate TLS in front of the release and keep
the console off untrusted networks.

When running behind an ingress controller or reverse proxy, set
`app.trustedProxies` to the controller CIDR. Without it, every login attempt is
counted against the controller address and the rate limiter throttles all
operators at once.

## Values

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/baarai/artex` | Image repository. Point it at your own build until the upstream image is published. |
| `image.tag` | `""` (chart `appVersion`) | Image tag. |
| `replicaCount` | `1` | Keep at 1: single-writer runtime state on a ReadWriteOnce volume. |
| `executor.uid` / `executor.gid` | `10001` | Identity of agent processes; `-1` disables the drop. |
| `database.dsn` | `""` | Full connection string; wins over the parts below and is stored in the Secret. |
| `database.host` | `""` | PostgreSQL host (required unless `dsn` or `secrets.existingSecret`). |
| `database.port` | `5432` | PostgreSQL port. |
| `database.user` / `database.name` | `artex` | PostgreSQL role and database. |
| `database.sslmode` | `disable` | Use `require` or `verify-full` off-node. |
| `database.password` | `""` | PostgreSQL password (required unless `dsn` or `secrets.existingSecret`). |
| `secrets.existingSecret` | `""` | Existing Secret with `POSTGRES_PASSWORD`, optionally `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `ARTEX_SECRET_KEY`, `ARTEX_PG_DSN`. |
| `secrets.secretKey` | `""` | `ARTEX_SECRET_KEY` encryption key; empty generates `keys/secret.key` at first start. |
| `llm.provider` / `llm.model` | `""` | Default model profile, also configurable in the UI. |
| `llm.baseURL` / `llm.proxy` | `""` | Custom endpoint and HTTP proxy for model calls. |
| `llm.privateEndpoints` | `""` | Exact `host:port` entries allowed on private addresses. |
| `llm.anthropicApiKey` / `llm.openaiApiKey` | `""` | Model credentials stored in the chart Secret. |
| `app.port` | `8787` | Console and API port. |
| `app.proxyPort` | `8788` | Recording proxy port, pod-internal. |
| `app.trustedProxies` | `""` | CIDRs whose `X-Forwarded-For` is trusted. |
| `app.updateCheck` | `false` | Opt-in GitHub release check (only outbound call made on its own). |
| `app.noiseProfile` | `""` | Target-request pacing: `off`, `quiet`, `balanced`, `aggressive`. |
| `app.targetUserAgent` | `""` | Forced User-Agent on target requests. |
| `app.taskBudgetTokens` / `_Turns`, `app.intentBudgetTokens` / `_Turns` | `""` | Hierarchical run budgets; empty or `0` means unlimited. |
| `extraEnv` / `extraEnvFrom` | `[]` | Additional environment entries. |
| `service.type` / `service.port` | `ClusterIP` / `8787` | Console Service. |
| `ingress.*` | disabled | Ingress with hosts, TLS and annotations. |
| `persistence.data.*` | `20Gi`, RWO | Runtime data claim (`enabled`, `existingClaim`, `size`, `storageClassName`). |
| `persistence.keys.*` | `1Gi`, RWO | Signing and secrets keys claim. |
| `skills.enabled` / `skills.existingClaim` | `false` / `""` | Mount an operator-owned skills directory over `/app/skills`. |
| `resources` | `500m`/`1Gi` → `2`/`4Gi` | The image bundles scanners and Chromium; an exploration runs several at once. |
| `probes.*` | enabled | Startup, readiness (`/api/ready`) and liveness (`/api/health`). |
| `serviceAccount.create` | `true` | ServiceAccount with token automount disabled (the app never calls the API). |
| `networkPolicy.enabled` | `false` | Restrict ingress; egress stays open for scanning unless `egress` is listed. |
| `podDisruptionBudget.enabled` | `false` | PDB for the single replica. |
| `nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints` | `{}` / `[]` | Scheduling. |
| `terminationGracePeriodSeconds` | `30` | Matches the application's graceful shutdown. |

## Publishing

The chart is distributed as an OCI artifact. Publishing is a manual step: this
repository's CI does not build charts, and adding a workflow here would tie a
release to a runner the fork does not own.

```bash
helm package charts/artex -d dist
helm registry login ghcr.io -u <owner>
helm push dist/artex-<version>.tgz oci://ghcr.io/<owner>/charts
```

The resulting reference is `oci://ghcr.io/<owner>/charts/artex`. GHCR creates
packages private: set the package to public, or give consumers registry
credentials before `helm install`.

Installing from the registry then needs no repository setup:

```bash
helm install artex oci://ghcr.io/<owner>/charts/artex --version 0.1.0
```

## Upgrades
The deployment uses the `Recreate` strategy: the new pod waits for the old one to
release the ReadWriteOnce volumes. The schema migrates automatically at startup,
and neither volume is touched by an upgrade.

`helm upgrade artex oci://ghcr.io/didlawowo/charts/artex --reuse-values`

## Security

Report vulnerabilities in ARTEX itself through the project's
[security policy](https://github.com/BaaRai/ARTEX/blob/main/SECURITY.md), not in a
public issue. This chart deploys a tool whose purpose is to attack targets: keep
it on a network segment you control, and treat its output and its data volume as
sensitive.
