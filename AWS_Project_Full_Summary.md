# AWS Secure Cloud Infrastructure Project — Full Summary
*Everything built, learned, and debugged so far. Built for cross-referencing against Microsoft-stack interview prep — AWS and Microsoft security concepts map onto each other more than they first appear to.*

---

## Project overview

Built a secure AWS "Landing Zone" (a hardened baseline cloud environment) entirely via Terraform (Infrastructure as Code), then deployed a containerized app onto it via Docker + Kubernetes (EKS), wrapped in AWS's native security services, with vulnerability remediation and a CI/CD security pipeline layered on top. Maps to a resume bullet about a "Secure Cloud Infrastructure & DevSecOps Platform."

---

## Part 1: Identity & Access Foundation

- **Two separate IAM identities**: a personal admin user (console access, MFA) and `terraform-deployer` (programmatic-only, used by Terraform). Deliberate separation of human vs. automation identity.
- **IAM roles with narrow trust policies** (`assume_role_policy`) for CloudTrail, EKS cluster, EKS nodes — each scoped to exactly what it needs via `sts:AssumeRole`, using AWS-managed policies (`AmazonEKSClusterPolicy`, etc.) rather than broad access.
- Root account MFA enabled separately from the personal IAM user's MFA.

**→ Microsoft-world equivalent:** this is the AWS version of Entra ID's least-privilege / RBAC / Conditional Access thinking — separate identities for humans vs. service principals, scoped role assignments instead of Global Admin for everything, MFA enforcement. PIM's "just-in-time privileged access" is conceptually the same idea as AWS's temporary STS credentials via AssumeRole — neither grants standing, permanent elevated access.

---

## Part 2: Logging, Detection & Compliance Services

| Service | What it does | Built via |
|---|---|---|
| **CloudTrail** | Records every API call in the account — the audit trail | Multi-region trail, KMS-encrypted, log file validation on |
| **KMS** | Encryption key management | Encrypts CloudTrail logs, `bucket_key_enabled` for cost efficiency |
| **GuardDuty** | Threat/anomaly detection (network, API activity, malware scanning) | Detector + EKS Runtime Monitoring + EKS Audit Log Monitoring add-ons |
| **Security Hub** | Aggregates findings from other services, scores against CIS/Foundational benchmarks | Subscribed to CIS AWS Foundations Benchmark v1.4.0 |
| **Macie** | Scans S3 for sensitive/PII data | One-time classification job on the CloudTrail logs bucket |
| **AWS Config** | Tracks resource configuration state over time, flags drift | Recorder + delivery channel + dedicated S3 bucket |
| **WAF** | Web traffic filtering (SQLi, XSS, known-bad-input rule sets) | Web ACL built with AWS managed rule groups; not yet attached to a live load balancer |
| **Amazon Inspector** | Continuous vulnerability scanning of ECR images | Enabled for ECR resource type |

**→ Microsoft-world equivalent — this is the most directly useful mapping for your prep:**
- CloudTrail ≈ Azure Activity Log / audit logging
- GuardDuty ≈ Microsoft Defender's threat detection role (EDR/XDR concept — watching for anomalous behavior)
- Security Hub ≈ Microsoft Secure Score / Defender's aggregated compliance dashboard
- AWS Config ≈ Azure Policy (continuous configuration compliance)
- Sentinel (Microsoft's SIEM) ≈ conceptually where Security Hub + GuardDuty findings would flow if this were a SIEM-centralized architecture — Sentinel's whole job is aggregating and correlating exactly this kind of finding across a fleet, using KQL instead of AWS's native dashboards.

---

## Part 3: Networking

Custom VPC (not AWS's default) with:
- 2 public + 2 private subnets across 2 Availability Zones
- Internet Gateway (public subnets' route to the internet)
- NAT Gateways, one per AZ (private subnets' outbound-only route)
- Route tables explicitly associated per subnet type

**Key lesson learned:** NAT Gateways *must* sit in public subnets because they themselves need a route to the Internet Gateway — private-only NAT is a contradiction. Public/private split exists specifically so backend compute (EKS nodes) is never directly internet-reachable; only the load balancer is.

**→ Microsoft-world equivalent:** this is the same thinking behind network segmentation/VLANs and Zero Trust network architecture — don't expose backend systems directly, force traffic through a controlled ingress point. Directly relevant to the JD's "network segmentation" and "Zero Trust" bullets.

---

## Part 4: Containerization & Kubernetes (EKS)

- Built a Flask app, containerized with Docker (switched from `python:3.11-slim` to `python:3.11-alpine` specifically to eliminate an oversized attack surface — unused Perl/glibc packages)
- Pushed to **ECR** (AWS's container registry)
- Deployed to **EKS** (AWS's managed Kubernetes) — cluster + node group, in private subnets
- Exposed via a Kubernetes `Service` (type LoadBalancer), successfully reached live over the internet
- Applied `securityContext` hardening (`runAsNonRoot`, `allowPrivilegeEscalation: false`) at the Kubernetes level, plus a non-root `USER` in the Dockerfile — defense in depth, two independent enforcement layers

**Real incidents debugged (good interview material):**
1. **Load balancer unreachable** — methodically isolated via: port-forward test (ruled out the app) → target health check (ruled out security groups) → listener config check → cross-zone load balancing (found single-AZ node + disabled cross-zone = ~50% of requests hitting nothing) → final root cause was a terminal line-wrap causing a truncated copy-paste of the DNS hostname.
2. **ECR immutable tag surprise** — `image_tag_mutability = "IMMUTABLE"` silently blocked `latest` from ever being reassigned to a new image push; diagnosed via digest/timestamp comparison; fixed by switching to explicit version tags (`v2`, etc.) as a permanent practice.
3. **GuardDuty/Macie blocked by AWS's "Free Plan"** account tier — a newer AWS account structure gating certain services entirely until upgrading to Paid Plan (no functional change to billing beyond the existing credit balance).
4. **Accidental resource resurrection** — an interrupted (Ctrl+C'd) `terraform apply` recreated already-destroyed NAT Gateways/EKS mid-flight because the code still described them; fixed by isolating cost-accruing, non-default resources (EKS, NAT Gateways, EIPs) into a separately-toggled `eks.tf.disabled` file so unrelated applies can't touch them.

**→ Microsoft-world equivalent:** the EKS troubleshooting sequence (isolate variables, verify each layer methodically before touching config) is the same disciplined incident-response process the JD asks for directly ("evidence collection, containment, service restoration, post-incident documentation"). The `.disabled`-file isolation pattern is a real change-management lesson — same spirit as change control / limiting blast radius.

---

## Part 5: Vulnerability Remediation

- **ECR image scan: 17 vulnerabilities → 0**, achieved by switching base images (Alpine over Debian-slim) rather than just patching — an attack-surface-reduction decision, not just patching.
- **Traced two "unfixable via requirements.txt" CVEs (msgpack, setuptools) to code vendored inside pip's own internals** — confirmed via pip's own public `vendor.txt` source file, not guesswork. Documented as accepted residual risk in a `.trivyignore` file with full justification, since no runtime code path exists and no user-facing fix is possible.
- **Security Hub Critical finding (missing AWS Config)** — diagnosed and remediated.
- **Deliberate risk acceptance: hardware MFA for root** — evaluated cost/benefit for a personal-scale account and documented the decision not to purchase a hardware key, since virtual MFA provides substantially equivalent protection at this scale.

**→ Microsoft-world equivalent:** this whole section is a direct rehearsal for the JD's "vulnerability scanning and remediation" and "post-incident documentation" bullets — the skill on display isn't just "found and fixed things," it's **triage**: knowing which findings are worth fixing, which are structurally unfixable, and which are acceptable to formally accept with documented reasoning. That triage judgment is exactly what a SOC/security-ops role expects day to day.

---

## Part 6: CI/CD Security Pipeline (GitHub Actions)

- Set up Git/GitHub from scratch, unified repo (`infrastructure/` + `App/` folders)
- Built a `.github/workflows/security-pipeline.yml` triggered on every push to `main`
- **Trivy** — container image vulnerability scanning (currently passing, with the two vendored-pip CVEs formally ignored via documented `.trivyignore` entries)
- **Checkov** — Terraform/IaC misconfiguration scanning (currently passing)
- **Semgrep** — SAST (static code analysis) — in progress; found real issues (missing Dockerfile `USER`, missing Kubernetes `securityContext`) which were genuinely fixed, plus one correctly-identified false positive (`host="0.0.0.0"` — required for container networking, suppressed with a documented inline `nosemgrep` comment rather than "fixed" in a way that would have broken the deployment)
- **Still to add:** OWASP Dependency-Check, SBOM generation

**→ Microsoft-world equivalent:** this is "shift-left security" / DevSecOps — the same philosophy behind wanting security requirements baked into technology projects from the start (a JD bullet). The pipeline itself is a form of security automation, directly relevant to the "security automation and scripting" bullet even though it's YAML/GitHub Actions rather than PowerShell.

---

## Current status

Bullet 1 (AWS security services + Docker + EKS): ~90% complete — only WAF reattachment/logging remains, deferred for cost reasons.
Bullet 2 (DevSecOps CI pipeline): ~60% complete — Trivy and Checkov live and passing, Semgrep fixes in progress, OWASP Dependency-Check and SBOM generation not yet started.
Projects 2 (Zero Trust IAM) and 3 (Detection Engineering/SIEM) from the original resume: not yet started — but Project 3 in particular will feel very familiar once the Microsoft-stack prep is done, since Sentinel/KQL is functionally the same skillset as the Security Hub/GuardDuty work already completed here, just on a different cloud provider.
