# Record corrections production release — 0.1.19+20

The user authorized immediate GitHub push, production deployment and website APK publication after the local implementation handoff, and made this the default for future Malva changes after required verification.

Source commit: `0afaf570eb8f475f35ec61713fb4c26083ae5271`, pushed atomically to `main` and `codex/chat-mycare-reference`. No schema or API changes. Functional changes and local verification are documented in [the implementation QA](2026-11-11-record-presence-corrections.md).

Evidence root: `D:/Project/Malva/2026-07-09/_qa_2026_11_11_record_corrections/`.

## Workflows

| Workflow | Run |
|---|---|
| Deploy Backend (API) | https://github.com/Chokobunni/malva-mental-health/actions/runs/42931165101 |
| Deploy Web App (/app) | https://github.com/Chokobunni/malva-mental-health/actions/runs/42931165102 |
| Build & Deploy APK | https://github.com/Chokobunni/malva-mental-health/actions/runs/42931165120 |
| Go Backend CI | https://github.com/Chokobunni/malva-mental-health/actions/runs/42931165130 |
| Flutter CI | https://github.com/Chokobunni/malva-mental-health/actions/runs/42931165380 |
| Security Gates | https://github.com/Chokobunni/malva-mental-health/actions/runs/42931165185 |

## Production checks

- Backend deployment completed successfully; the service restart and workflow health check passed. Independent `https://api.malva.web.id/healthz` returns HTTP200 and `status: ok` after deployment.
- Web app deployment completed successfully. `https://malva.web.id/app/` and the landing page return HTTP200. Public `/app/version.json` reports version0.1.19/build20. Existing landing download links point to `/downloads/malva-latest.apk`.
- Verified all50previously tested source/configuration files against the frozen QA hashes before committing. Local full Flutter1152tests, clean analyzer and PostgreSQL/backend gates remain applicable; only release-policy/documentation changed afterward.

## Published APK

- Public canonical download: https://malva.web.id/downloads/malva-latest.apk . HTTP200 and Android package content type verified by downloading the actual file without a query string.
- Published version0.1.19/code20, 31,928,551bytes. Its SHA-256 is `eacadcc1907b6f58cb0461fbb19ff7603b9c2c773297d55690810dda7cd57da0`; bytes match both the `malva-apk` artifact and `SHA256SUMS.txt` from workflow42931165120.
- Signature verified against the existing release certificate SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`. Actual compiled `lib/arm64-v8a/libapp.so` verified, including the production API and Google client ID defines; the workflow targets ARM64, independently of other packaged plugin/engine library directories.
- Evidence: `published-apk-verification.json`, `published-apk-signature.txt`, `published-apk-badging.txt`, `published-apk-libraries.json`, and `ci-release-artifact/`.

## Final CI conclusions

All six workflows listed above completed successfully for source commit0afaf57. Flutter CI includes clean analyze/format/WIB/platform gates, passing test runs in both Asia/Jakarta and UTC test environments, and successful Web/Windows builds. Go Backend CI includes PostgreSQL integration/race tests, lint, binary and Docker builds. Security Gates passed. Workflow JSON evidence is preserved in `production-workflows-final.json` and `workflow-<run>.json`.

The prior deployment restriction in the local handoff has been superseded by the user's explicit release instruction. The repository guide and a memory extension now preserve the default push/deploy/website-APK preference for future work.

## Limits

Production checks verify deployment health, web version and the published binary. They do not constitute an authenticated two-account clinical flow or physical-device test. The local universal APK and workflow-published ARM64 APK use the same version/source and release certificate but have different ABI packaging/checksums.
