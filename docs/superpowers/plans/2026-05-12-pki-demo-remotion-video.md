# PKI Demo Remotion Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repeatable first-slice workflow that captures the existing `make demo` PKI walkthrough and renders it as a terminal-first Remotion presentation video with on-screen presenter notes.

**Architecture:** Add a small `video/` workspace. The existing `pki-demo.sh` remains the source of truth, a capture script runs it unattended and records output, a Node scene builder parses and redacts that output into scene JSON, and a Remotion app renders those scenes with a terminal-first teaching layout.

**Tech Stack:** Bash, Make, Node.js built-in test runner, Remotion/React/TypeScript, existing Vault/Docker/OpenSSL/JQ demo tooling.

---

## Reference documents

- Spec: `docs/superpowers/specs/2026-05-12-pki-demo-remotion-video-design.md`
- Demo source: `pki-demo.sh`
- Existing Make entrypoints: `Makefile`
- Existing preflight: `demo-preflight.sh`
- Remotion guidance: use `useCurrentFrame()`, `interpolate()`, `Series`, and `Composition`; do not use CSS transitions or CSS animations.

## File structure

Create or modify these files:

- Modify: `.gitignore`
  - Ignore visual companion state and generated video artefacts.
- Modify: `pki-demo.sh`
  - Add capture/auto-advance support without changing the interactive path.
- Modify: `Makefile`
  - Add `demo-video-capture`, `demo-video-preview`, `demo-video-still`, and `demo-video-render` targets.
- Create: `video/capture-demo.sh`
  - Runs preflight, captures `pki-demo.sh` output, and invokes the scene builder.
- Create: `video/build-scenes.js`
  - Parses raw transcript, redacts sensitive material, and writes Remotion props JSON.
- Create: `video/scene-metadata.json`
  - Presenter notes and PKI phase labels keyed by demo step title.
- Create: `video/test/build-scenes.test.js`
  - Node built-in tests for parsing and redaction.
- Create: `video/test/fixtures/pki-demo-transcript.fixture`
  - Sanitised transcript fixture with no secret-shaped values.
- Create: `video/scenes/pki-demo-scenes.example.json`
  - Small committed sample props file for Remotion preview/still checks before a real capture exists.
- Generated, ignored: `video/scenes/pki-demo-scenes.json`
  - Real generated props from capture.
- Generated, ignored: `video/captures/`
  - Raw transcripts; can include sensitive material and must not be committed.
- Create via scaffold, then edit: `video/remotion/package.json`
- Create via scaffold, then edit: `video/remotion/src/index.ts`
- Create via scaffold, then edit: `video/remotion/src/Root.tsx`
- Create: `video/remotion/src/PkiDemoVideo.tsx`
- Create: `video/remotion/src/types.ts`
- Create: `video/remotion/src/theme.ts`

## Implementation notes

- The first slice supports only `make demo`/`pki-demo.sh`.
- The capture script should invoke `pki-demo.sh` directly, while the user-facing entrypoint remains `make demo-video-capture`.
- Do not commit `.superpowers/`, raw captures, generated scene JSON, render outputs, `node_modules`, or generated certificates/keys.
- Preserve existing dirty worktree changes. Only add/commit files touched by each task.
- Use Australian English in user-facing documentation and presenter notes.

---

### Task 1: Ignore generated video artefacts

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add ignore entries**

Append this block to `.gitignore`:

```gitignore

# Superpowers visual brainstorming artefacts
.superpowers/

# PKI demo video generated artefacts
video/captures/
video/scenes/pki-demo-scenes.json
video/remotion/out/
video/remotion/dist/
video/remotion/node_modules/
```

- [ ] **Step 2: Verify ignore behaviour**

Run:

```bash
git check-ignore -v .superpowers/brainstorm/example video/captures/example.log video/scenes/pki-demo-scenes.json video/remotion/out/pki-demo.mp4
```

Expected: each path is reported as ignored by `.gitignore`.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore generated video artefacts" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Add unattended capture mode to `pki-demo.sh`

**Files:**
- Modify: `pki-demo.sh:13-27`

- [ ] **Step 1: Update demo speed configuration**

Replace the current speed block:

```bash
# Set demo speed
TYPE_SPEED=200
DEMO_PROMPT=""
```

with:

```bash
# Set demo speed. Capture mode disables simulated typing so automated transcripts
# do not depend on pv or wall-clock typing speed.
if [ -n "${PKI_DEMO_AUTO_ADVANCE_SECONDS:-}" ]; then
    PROMPT_TIMEOUT="$PKI_DEMO_AUTO_ADVANCE_SECONDS"
    unset TYPE_SPEED
else
    TYPE_SPEED="${TYPE_SPEED:-200}"
fi
DEMO_PROMPT=""
```

Rationale: capture will run `./pki-demo.sh -d` so `demo-magic.sh` does not require `pv`; this block keeps `TYPE_SPEED` unset in capture mode after `demo-magic.sh` is sourced.

- [ ] **Step 2: Syntax-check the script**

Run:

```bash
bash -n pki-demo.sh
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify interactive behaviour is preserved**

Run:

```bash
grep -n "PKI_DEMO_AUTO_ADVANCE_SECONDS" pki-demo.sh
```

Expected: one guarded block only. The default path still sets `TYPE_SPEED` to `200`.

- [ ] **Step 4: Commit**

```bash
git add pki-demo.sh
git commit -m "feat: add PKI demo capture pacing mode" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Add scene metadata and parser tests first

**Files:**
- Create: `video/scene-metadata.json`
- Create: `video/test/fixtures/pki-demo-transcript.fixture`
- Create: `video/test/build-scenes.test.js`

- [ ] **Step 1: Create scene metadata**

Create `video/scene-metadata.json` with notes for every first-slice scene:

```json
{
  "Step 1: Verify Vault Status": {
    "phase": "Environment",
    "presenterNote": "Confirm Vault is reachable and unsealed before changing PKI state."
  },
  "Step 2: Review PKI Secrets Engines": {
    "phase": "PKI baseline",
    "presenterNote": "Show the root and intermediate PKI mounts that form the trust hierarchy."
  },
  "Step 3: Generate Root Certificate": {
    "phase": "Root CA",
    "presenterNote": "Create the root trust anchor that signs the rest of the PKI hierarchy."
  },
  "Step 4: Configure PKI URLs": {
    "phase": "Distribution",
    "presenterNote": "Publish issuing certificate and CRL endpoints so clients know where to validate trust."
  },
  "Step 5: Generate Intermediate Certificate": {
    "phase": "Intermediate CA",
    "presenterNote": "Generate and sign an intermediate CA so day-to-day issuance does not use the root directly."
  },
  "Step 6: Configure Intermediate CA URLs": {
    "phase": "Distribution",
    "presenterNote": "Configure the intermediate CA endpoints before importing the signed issuer."
  },
  "Step 7: Create Certificate Role": {
    "phase": "Issuance policy",
    "presenterNote": "Define which names, SANs, and lifetimes this PKI role is allowed to issue."
  },
  "Step 8: Issue a Server Certificate": {
    "phase": "Leaf issuance",
    "presenterNote": "Issue a leaf certificate from the intermediate CA using the role constraints."
  },
  "Step 8.25: Sign a Locally Generated CSR": {
    "phase": "Key custody",
    "presenterNote": "Show the CSR path for teams that need the private key to stay outside Vault."
  },
  "Step 9: Save Certificate Components": {
    "phase": "Application files",
    "presenterNote": "Save certificate, key, and CA chain components into files an application can consume."
  },
  "Step 10: Verify Certificate Details": {
    "phase": "Inspection",
    "presenterNote": "Inspect the issued certificate to confirm subject, issuer, validity, and extensions."
  },
  "Step 11: Examine Certificate Chain": {
    "phase": "Trust validation",
    "presenterNote": "Verify the leaf certificate chains through the intermediate CA to the trusted root."
  },
  "Step 12: Certificate Revocation": {
    "phase": "Revocation",
    "presenterNote": "Revoke a certificate by serial number so it can no longer be trusted."
  },
  "Step 13: Certificate Revocation List": {
    "phase": "Revocation",
    "presenterNote": "Read the CRL and confirm revoked certificate information is published."
  },
  "Demo Summary": {
    "phase": "Summary",
    "presenterNote": "Recap the operator path from trust bootstrap through issuance, verification, and revocation."
  }
}
```

- [ ] **Step 2: Create a sanitised parser fixture**

Create `video/test/fixtures/pki-demo-transcript.fixture`:

```text
==== Step 1: Verify Vault Status ====
Let's start by checking our Vault instance:

vault status
Key             Value
---             -----
Seal Type       shamir
Sealed          false
Token           [token omitted from fixture]

==== Step 8: Issue a Server Certificate ====
Now let's issue a certificate for a web server:

vault write pki_int/issue/web-server common_name="web.example.com" ttl="24h"
Key                 Value
---                 -----
certificate         [certificate body omitted from fixture]
private_key         [private key omitted from fixture]
expiration          1893456000

==== Demo Summary ====
PKI Demo Completed Successfully!
```

- [ ] **Step 3: Write failing Node tests**

Create `video/test/build-scenes.test.js`:

```javascript
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  parseTranscript,
  redactSensitiveOutput,
  buildScenes,
} = require("../build-scenes");

const fixturePath = path.join(__dirname, "fixtures", "pki-demo-transcript.fixture");
const metadataPath = path.join(__dirname, "..", "scene-metadata.json");

test("parseTranscript extracts demo scenes from headings", () => {
  const transcript = readFileSync(fixturePath, "utf8");
  const scenes = parseTranscript(transcript);

  assert.equal(scenes.length, 3);
  assert.equal(scenes[0].title, "Step 1: Verify Vault Status");
  assert.equal(scenes[1].title, "Step 8: Issue a Server Certificate");
  assert.equal(scenes[2].title, "Demo Summary");
});

test("redactSensitiveOutput removes private keys and token-shaped values", () => {
  const fakeVaultToken = ["hvs", "fake-token-for-test"].join(".");
  const fakePrivateKey = [
    "-----BEGIN RSA " + "PRIVATE KEY-----",
    "MIIFAKEPRIVATEKEY",
    "-----END RSA " + "PRIVATE KEY-----",
  ].join("\n");
  const redacted = redactSensitiveOutput(`Token ${fakeVaultToken}\n${fakePrivateKey}`);

  assert.doesNotMatch(redacted, /MIIFAKEPRIVATEKEY/);
  assert.doesNotMatch(redacted, new RegExp(fakeVaultToken.replace(".", "\\.")));
  assert.match(redacted, /\[REDACTED PRIVATE KEY\]/);
  assert.match(redacted, /\[REDACTED TOKEN\]/);
});

test("buildScenes enriches scenes with metadata", () => {
  const transcript = readFileSync(fixturePath, "utf8");
  const metadata = JSON.parse(readFileSync(metadataPath, "utf8"));
  const props = buildScenes(transcript, metadata);

  assert.equal(props.scenes[1].phase, "Leaf issuance");
  assert.match(props.scenes[1].presenterNote, /Issue a leaf certificate/);
  assert.equal(props.source, "pki-demo");
});
```

- [ ] **Step 4: Run tests to verify they fail**

Run:

```bash
node --test video/test/build-scenes.test.js
```

Expected: FAIL because `video/build-scenes.js` does not exist yet.

- [ ] **Step 5: Verify fixture hygiene**

Run:

```bash
if grep -E "BEGIN .*PRIVATE KEY|BEGIN CERTIFICATE|(hvs|hvb|s)\\." video/test/fixtures/*.fixture; then
  echo "ERROR: committed fixture contains sensitive-looking material"
  exit 1
fi
```

Expected: no matches.

- [ ] **Step 6: Commit tests and metadata**

```bash
git add video/scene-metadata.json video/test/fixtures/pki-demo-transcript.fixture video/test/build-scenes.test.js
git commit -m "test: add PKI demo scene parser coverage" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Implement the scene builder

**Files:**
- Create: `video/build-scenes.js`
- Create: `video/scenes/pki-demo-scenes.example.json`

- [ ] **Step 1: Implement parser and redaction**

Create `video/build-scenes.js`:

```javascript
#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const ANSI_PATTERN = /\u001b\[[0-9;]*m/g;
const HEADING_PATTERN = /^=+\s*(Step\s+[^=]+|Demo Summary)\s*=+\s*$/;
const TOKEN_PATTERN = /\b(hvs|hvb|s)\.[A-Za-z0-9._-]+/g;
const PRIVATE_KEY_PATTERN =
  /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g;

function stripAnsi(value) {
  return value.replace(ANSI_PATTERN, "");
}

function redactSensitiveOutput(value) {
  return stripAnsi(value)
    .replace(PRIVATE_KEY_PATTERN, "[REDACTED PRIVATE KEY]")
    .replace(TOKEN_PATTERN, "[REDACTED TOKEN]");
}

function normaliseLine(line) {
  return line.replace(/\s+$/g, "");
}

function slugify(title) {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function isCommandLine(line) {
  return /^(vault|openssl|ls|cat)\b/.test(line.trim());
}

function parseTranscript(transcript) {
  const cleanTranscript = redactSensitiveOutput(transcript);
  const lines = cleanTranscript.split(/\r?\n/).map(normaliseLine);
  const scenes = [];
  let current = null;

  for (const line of lines) {
    const heading = line.match(HEADING_PATTERN);

    if (heading) {
      if (current) {
        scenes.push(current);
      }

      current = {
        id: slugify(heading[1]),
        title: heading[1],
        transcriptLines: [],
        commands: [],
      };
      continue;
    }

    if (!current) {
      continue;
    }

    current.transcriptLines.push(line);
    if (isCommandLine(line)) {
      current.commands.push(line.trim());
    }
  }

  if (current) {
    scenes.push(current);
  }

  return scenes.map((scene) => ({
    ...scene,
    transcriptLines: trimBlankEdges(scene.transcriptLines),
  }));
}

function trimBlankEdges(lines) {
  let start = 0;
  let end = lines.length;

  while (start < end && lines[start] === "") {
    start += 1;
  }
  while (end > start && lines[end - 1] === "") {
    end -= 1;
  }

  return lines.slice(start, end);
}

function buildScenes(transcript, metadata) {
  const scenes = parseTranscript(transcript).map((scene, index) => {
    const sceneMetadata = metadata[scene.title] || {};

    return {
      ...scene,
      order: index + 1,
      phase: sceneMetadata.phase || "PKI demo",
      presenterNote:
        sceneMetadata.presenterNote ||
        "Walk through this PKI demo step and connect the command output to the operator workflow.",
    };
  });

  if (scenes.length === 0) {
    throw new Error("No demo scenes found in transcript");
  }

  return {
    source: "pki-demo",
    generatedAt: new Date().toISOString(),
    scenes,
  };
}

function parseArgs(argv) {
  const args = {};

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      args[arg.slice(2)] = argv[i + 1];
      i += 1;
    }
  }

  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.input || !args.metadata || !args.output) {
    throw new Error(
      "Usage: node video/build-scenes.js --input <transcript> --metadata <metadata.json> --output <scenes.json>",
    );
  }

  const transcript = fs.readFileSync(args.input, "utf8");
  const metadata = JSON.parse(fs.readFileSync(args.metadata, "utf8"));
  const props = buildScenes(transcript, metadata);
  fs.mkdirSync(path.dirname(args.output), { recursive: true });
  fs.writeFileSync(args.output, `${JSON.stringify(props, null, 2)}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  }
}

module.exports = {
  buildScenes,
  parseTranscript,
  redactSensitiveOutput,
};
```

- [ ] **Step 2: Run parser tests**

Run:

```bash
node --test video/test/build-scenes.test.js
```

Expected: PASS.

- [ ] **Step 3: Generate the example scenes file**

Run:

```bash
node video/build-scenes.js \
  --input video/test/fixtures/pki-demo-transcript.fixture \
  --metadata video/scene-metadata.json \
  --output video/scenes/pki-demo-scenes.example.json
```

Expected: `video/scenes/pki-demo-scenes.example.json` exists.

- [ ] **Step 4: Verify redaction in the generated example**

Run:

```bash
if grep -E "MIIFAKEPRIVATEKEY|(hvs|hvb|s)\\." video/scenes/pki-demo-scenes.example.json; then
  echo "ERROR: generated example contains sensitive-looking fixture data"
  exit 1
fi
```

Expected: no matches.

- [ ] **Step 5: Commit parser implementation**

```bash
git add video/build-scenes.js video/scenes/pki-demo-scenes.example.json
git commit -m "feat: build PKI demo scenes from transcript" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Add unattended capture script and Make target

**Files:**
- Create: `video/capture-demo.sh`
- Modify: `Makefile`

- [ ] **Step 1: Create capture script**

Create `video/capture-demo.sh`:

```bash
#!/bin/bash

set -euo pipefail

AUTO_ADVANCE_SECONDS="${PKI_DEMO_AUTO_ADVANCE_SECONDS:-1}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
CAPTURE_DIR="video/captures"
SCENE_DIR="video/scenes"
RAW_CAPTURE="${CAPTURE_DIR}/pki-demo-${TIMESTAMP}.log"
SCENES_OUTPUT="${SCENE_DIR}/pki-demo-scenes.json"

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: Missing required command: $1"
        exit 1
    fi
}

for cmd in bash docker vault openssl jq curl node tee; do
    check_command "$cmd"
done

mkdir -p "$CAPTURE_DIR" "$SCENE_DIR"

echo "Running demo preflight..."
./demo-preflight.sh

echo
echo "Capturing PKI demo transcript to ${RAW_CAPTURE}"
set +e
PKI_DEMO_AUTO_ADVANCE_SECONDS="$AUTO_ADVANCE_SECONDS" ./pki-demo.sh -d 2>&1 | tee "$RAW_CAPTURE"
DEMO_STATUS=${PIPESTATUS[0]}
set -e

if [ "$DEMO_STATUS" -ne 0 ]; then
    echo "ERROR: Demo capture failed with exit code ${DEMO_STATUS}"
    echo "Raw transcript preserved at ${RAW_CAPTURE}"
    exit "$DEMO_STATUS"
fi

echo
echo "Building Remotion scene data at ${SCENES_OUTPUT}"
node video/build-scenes.js \
    --input "$RAW_CAPTURE" \
    --metadata video/scene-metadata.json \
    --output "$SCENES_OUTPUT"

echo
echo "OK: Capture complete"
echo "Raw transcript: ${RAW_CAPTURE}"
echo "Scene data:     ${SCENES_OUTPUT}"
```

- [ ] **Step 2: Make the capture script executable**

Run:

```bash
chmod +x video/capture-demo.sh
```

- [ ] **Step 3: Add Make targets**

Update `.PHONY` in `Makefile` to include:

```make
demo-video-capture demo-video-preview demo-video-still demo-video-render
```

Add these targets near the existing demo targets:

```make
demo-video-capture: ## Capture make demo output and build Remotion scene data
	./video/capture-demo.sh

demo-video-preview: ## Open Remotion Studio for the PKI demo video
	cd video/remotion && npm run preview

demo-video-still: ## Render a low-scale still frame for the PKI demo video
	cd video/remotion && npm run still:pki

demo-video-render: ## Render the PKI demo video from generated scene data
	cd video/remotion && npm run render:pki
```

- [ ] **Step 4: Syntax-check changed shell files**

Run:

```bash
bash -n video/capture-demo.sh pki-demo.sh demo-preflight.sh
```

Expected: no output, exit code `0`.

- [ ] **Step 5: Verify Make help sees the new targets**

Run:

```bash
make help | grep demo-video
```

Expected: the four `demo-video-*` targets are listed.

- [ ] **Step 6: Commit capture wiring**

```bash
git add Makefile video/capture-demo.sh
git commit -m "feat: capture PKI demo for video rendering" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Scaffold the Remotion project

**Files:**
- Create: `video/remotion/package.json`
- Create: `video/remotion/package-lock.json`
- Create: `video/remotion/src/index.ts`
- Create: `video/remotion/src/Root.tsx`

- [ ] **Step 1: Scaffold a blank Remotion app**

Run:

```bash
npx create-video@latest --yes --blank --no-tailwind video/remotion
```

Expected: `video/remotion/package.json` and `video/remotion/src/Root.tsx` exist.

- [ ] **Step 2: Install dependencies**

Run:

```bash
npm --prefix video/remotion install
```

Expected: `video/remotion/package-lock.json` exists and install exits successfully.

- [ ] **Step 3: Add package scripts**

Update `video/remotion/package.json` scripts so they include:

```json
{
  "preview": "remotion studio src/index.ts",
  "still:pki": "remotion still src/index.ts PkiDemoVideo --frame=30 --scale=0.25 --props=../scenes/pki-demo-scenes.example.json",
  "render:pki": "remotion render src/index.ts PkiDemoVideo out/pki-demo.mp4 --props=../scenes/pki-demo-scenes.json",
  "render:pki:example": "remotion render src/index.ts PkiDemoVideo out/pki-demo-example.mp4 --props=../scenes/pki-demo-scenes.example.json"
}
```

Preserve any useful existing scaffolded scripts if present.

- [ ] **Step 4: Verify the scaffold compiles before custom components**

Run:

```bash
npm --prefix video/remotion exec remotion compositions src/index.ts
```

Expected: Remotion lists at least one scaffolded composition.

- [ ] **Step 5: Commit scaffold**

```bash
git add video/remotion/package.json video/remotion/package-lock.json video/remotion/src
git commit -m "chore: scaffold Remotion video project" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Implement the terminal-first Remotion composition

**Files:**
- Modify: `video/remotion/src/index.ts`
- Modify: `video/remotion/src/Root.tsx`
- Create: `video/remotion/src/PkiDemoVideo.tsx`
- Create: `video/remotion/src/types.ts`
- Create: `video/remotion/src/theme.ts`

- [ ] **Step 1: Define scene types**

Create `video/remotion/src/types.ts`:

```ts
export type DemoScene = {
  id: string;
  order: number;
  title: string;
  phase: string;
  presenterNote: string;
  commands: string[];
  transcriptLines: string[];
};

export type PkiDemoVideoProps = {
  source: "pki-demo";
  generatedAt: string;
  scenes: DemoScene[];
};
```

- [ ] **Step 2: Define shared theme values**

Create `video/remotion/src/theme.ts`:

```ts
export const theme = {
  background: "#0b1020",
  panel: "#111827",
  panelLight: "#f8fafc",
  terminalText: "#d1fae5",
  accent: "#60a5fa",
  accentSoft: "#dbeafe",
  success: "#86efac",
  text: "#0f172a",
  muted: "#64748b",
  fontSans: "Inter, Arial, sans-serif",
  fontMono: "Menlo, Monaco, Consolas, monospace",
};
```

- [ ] **Step 3: Implement composition component**

Create `video/remotion/src/PkiDemoVideo.tsx`. Use `Series`, `useCurrentFrame()`, `useVideoConfig()`, and `interpolate()` for Remotion-safe animation:

```tsx
import React from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  Series,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import type { DemoScene, PkiDemoVideoProps } from "./types";
import { theme } from "./theme";

const framesForScene = (scene: DemoScene, fps: number) => {
  const lineCount = Math.max(scene.transcriptLines.length, 8);
  return Math.min(Math.max(Math.ceil(lineCount * 0.45 * fps), 5 * fps), 14 * fps);
};

const Terminal = ({ scene }: { scene: DemoScene }) => {
  const frame = useCurrentFrame();
  const visibleLines = Math.max(1, Math.floor(frame / 3));
  const lines = scene.transcriptLines.slice(0, visibleLines);

  return (
    <div
      style={{
        background: theme.panel,
        borderRadius: 28,
        color: theme.terminalText,
        fontFamily: theme.fontMono,
        fontSize: 25,
        height: "100%",
        lineHeight: 1.35,
        overflow: "hidden",
        padding: 34,
        boxShadow: "0 28px 80px rgba(0,0,0,0.32)",
      }}
    >
      <div style={{ color: theme.accent, marginBottom: 22 }}>{scene.title}</div>
      {lines.map((line, index) => (
        <div
          key={`${scene.id}-${index}`}
          style={{
            color: scene.commands.includes(line.trim()) ? "#fef3c7" : theme.terminalText,
            whiteSpace: "pre-wrap",
          }}
        >
          {line || " "}
        </div>
      ))}
    </div>
  );
};

const PresenterPanel = ({ scene }: { scene: DemoScene }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 18], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

  return (
    <div
      style={{
        background: theme.panelLight,
        borderRadius: 28,
        color: theme.text,
        height: "100%",
        opacity,
        padding: 34,
      }}
    >
      <div
        style={{
          color: theme.muted,
          fontSize: 20,
          fontWeight: 700,
          letterSpacing: 2,
          textTransform: "uppercase",
        }}
      >
        What I am doing
      </div>
      <h2 style={{ fontSize: 42, lineHeight: 1.08, margin: "20px 0 18px" }}>
        {scene.phase}
      </h2>
      <p style={{ color: "#334155", fontSize: 27, lineHeight: 1.3, margin: 0 }}>
        {scene.presenterNote}
      </p>
      <div
        style={{
          background: theme.accentSoft,
          borderRadius: 999,
          height: 10,
          marginTop: 36,
          overflow: "hidden",
        }}
      >
        <div
          style={{
            background: theme.accent,
            height: "100%",
            width: `${Math.min(scene.order * 7, 100)}%`,
          }}
        />
      </div>
      <p style={{ color: theme.muted, fontSize: 20, marginTop: 14 }}>
        Operator PKI path - scene {scene.order}
      </p>
    </div>
  );
};

const SceneFrame = ({ scene }: { scene: DemoScene }) => (
  <AbsoluteFill
    style={{
      background: theme.background,
      fontFamily: theme.fontSans,
      padding: 54,
    }}
  >
    <div
      style={{
        color: "white",
        display: "flex",
        justifyContent: "space-between",
        marginBottom: 28,
      }}
    >
      <div style={{ fontSize: 30, fontWeight: 800 }}>HashiCorp Vault PKI Demo</div>
      <div style={{ color: "#bfdbfe", fontSize: 24 }}>{scene.phase}</div>
    </div>
    <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 28, flex: 1 }}>
      <Terminal scene={scene} />
      <PresenterPanel scene={scene} />
    </div>
  </AbsoluteFill>
);

export const PkiDemoVideo = (props: PkiDemoVideoProps) => {
  const { fps } = useVideoConfig();

  if (!props.scenes?.length) {
    throw new Error("PkiDemoVideo requires at least one scene");
  }

  return (
    <Series>
      {props.scenes.map((scene) => (
        <Series.Sequence key={scene.id} durationInFrames={framesForScene(scene, fps)}>
          <SceneFrame scene={scene} />
        </Series.Sequence>
      ))}
    </Series>
  );
};

export const getPkiDemoDuration = (props: PkiDemoVideoProps, fps: number) =>
  props.scenes.reduce((total, scene) => total + framesForScene(scene, fps), 0);
```

- [ ] **Step 4: Wire Root composition**

Update `video/remotion/src/Root.tsx`:

```tsx
import { Composition, type CalculateMetadataFunction } from "remotion";
import { PkiDemoVideo, getPkiDemoDuration } from "./PkiDemoVideo";
import type { PkiDemoVideoProps } from "./types";
import exampleScenes from "../../scenes/pki-demo-scenes.example.json";

const fps = 30;

const calculateMetadata: CalculateMetadataFunction<PkiDemoVideoProps> = ({ props }) => ({
  durationInFrames: getPkiDemoDuration(props, fps),
  fps,
  height: 1080,
  width: 1920,
});

export const RemotionRoot = () => (
  <Composition
    id="PkiDemoVideo"
    component={PkiDemoVideo}
    calculateMetadata={calculateMetadata}
    defaultProps={exampleScenes as PkiDemoVideoProps}
    fps={fps}
    height={1080}
    width={1920}
  />
);
```

- [ ] **Step 5: Wire Remotion entrypoint**

Ensure `video/remotion/src/index.ts` registers the root:

```ts
import { registerRoot } from "remotion";
import { RemotionRoot } from "./Root";

registerRoot(RemotionRoot);
```

- [ ] **Step 6: Validate composition listing**

Run:

```bash
npm --prefix video/remotion exec remotion compositions src/index.ts
```

Expected: output includes `PkiDemoVideo`.

- [ ] **Step 7: Render a low-scale still from example data**

Run:

```bash
npm --prefix video/remotion run still:pki
```

Expected: Remotion renders a still successfully.

- [ ] **Step 8: Commit Remotion composition**

```bash
git add video/remotion/src video/remotion/package.json
git commit -m "feat: render PKI demo terminal video" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: Wire render commands and documentation

**Files:**
- Modify: `README.md`
- Modify: `Makefile`

- [ ] **Step 1: Add README video workflow section**

Add a short section after the existing main demos section in `README.md`:

```markdown
### PKI demo video workflow

```bash
make demo-video-capture
make demo-video-preview
make demo-video-render
```

The video workflow captures the operator PKI walkthrough from `make demo`, converts the transcript into Remotion scene data, and renders a terminal-first presentation video with presenter notes. Raw captures and generated scene data are local artefacts and are ignored by git because they can include sensitive demo output.
```

- [ ] **Step 2: Verify generated scene render target is clear**

Confirm `Makefile` includes:

```make
demo-video-render: ## Render the PKI demo video from generated scene data
	cd video/remotion && npm run render:pki
```

This target intentionally requires `video/scenes/pki-demo-scenes.json`, which is created by `make demo-video-capture`.

- [ ] **Step 3: Run doc-free validation commands**

Run:

```bash
make help | grep demo-video
npm --prefix video/remotion run still:pki
```

Expected: Make help lists targets; Remotion still render succeeds using example data.

- [ ] **Step 4: Commit docs and command polish**

```bash
git add README.md Makefile
git commit -m "docs: document PKI demo video workflow" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Run end-to-end capture and render validation

**Files:**
- Generated only: `video/captures/*`
- Generated only: `video/scenes/pki-demo-scenes.json`
- Generated only: `video/remotion/out/*`

- [ ] **Step 1: Confirm environment is ready**

Run:

```bash
make preflight
```

Expected: exits `0`. If Vault is not running, run `make setup` first.

- [ ] **Step 2: Capture the real demo**

Run:

```bash
make demo-video-capture
```

Expected:

- capture completes without manual Enter key presses,
- a raw transcript is written under `video/captures/`,
- `video/scenes/pki-demo-scenes.json` is generated,
- output says `OK: Capture complete`.

- [ ] **Step 3: Verify generated scene redaction**

Run:

```bash
if grep -E "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|(hvs|hvb|s)\\." video/scenes/pki-demo-scenes.json; then
  echo "ERROR: generated scene data contains sensitive material"
  exit 1
fi
```

Expected: no matches.

- [ ] **Step 4: Render the full video**

Run:

```bash
make demo-video-render
```

Expected: `video/remotion/out/pki-demo.mp4` is created.

- [ ] **Step 5: Check ignored generated files are not staged**

Run:

```bash
git --no-pager status --short --ignored video/captures video/scenes video/remotion/out
```

Expected: generated files appear as ignored or untracked only as intended; do not stage them.

- [ ] **Step 6: Final verification**

Run:

```bash
node --test video/test/build-scenes.test.js
bash -n video/capture-demo.sh pki-demo.sh
npm --prefix video/remotion exec remotion compositions src/index.ts
```

Expected: all commands pass.

- [ ] **Step 7: Commit any final source fixes only**

If any source fixes were needed during end-to-end validation:

```bash
git add <source-files-only>
git commit -m "fix: stabilise PKI demo video workflow" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Do not commit generated captures, generated scene JSON, rendered videos, certificates, keys, or `.superpowers/`.

---

## Completion criteria

- `make demo-video-capture` runs the `pki-demo.sh` operator walkthrough unattended.
- `video/scenes/pki-demo-scenes.json` is generated from real captured output and redacted.
- `make demo-video-preview` opens the Remotion Studio.
- `make demo-video-still` renders a low-scale still using sample data.
- `make demo-video-render` renders `video/remotion/out/pki-demo.mp4` using generated data.
- Parser tests pass with `node --test video/test/build-scenes.test.js`.
- Generated raw captures, generated scene JSON, Remotion outputs, and visual companion files are ignored by git.
