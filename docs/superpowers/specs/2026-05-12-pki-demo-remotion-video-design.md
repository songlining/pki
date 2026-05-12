# PKI demo Remotion video design

## Problem

Create a repeatable way to turn the existing `make demo` operator PKI walkthrough into a presentation-style video. The video should step through the real demo commands and results while also explaining what the presenter is doing at each stage.

The first slice is intentionally scoped to `make demo` only. Vault Agent, rotation, webcam, voiceover, and process-supervisor flows are follow-on work that should reuse the same capture and rendering pipeline later.

## Goals

- Run the existing operator PKI demo unattended with fixed pacing.
- Capture real terminal command output from the demo run.
- Convert the capture into structured scene data.
- Render a Remotion video with a terminal-first teaching layout.
- Show presenter-style overlays that explain intent, not a webcam or voiceover.
- Keep `pki-demo.sh` as the source of truth for the operational walkthrough.

## Non-goals

- Support `make agent-demo`, `make watch-rotation`, or `make process-demo` in the first slice.
- Add webcam picture-in-picture.
- Add recorded or AI-generated voiceover.
- Replace the existing interactive demo with a video-only workflow.
- Hard-code command output that can drift from a real demo run.

## Recommended approach

Use a capture-driven Remotion pipeline:

1. A Make target prepares the demo environment and starts unattended capture.
2. The capture script runs `pki-demo.sh` with fixed auto-advance pauses.
3. The raw terminal transcript is saved under `video/captures/`.
4. A scene builder parses the transcript into `video/scenes/pki-demo-scenes.json`.
5. The Remotion composition reads the JSON and renders a terminal-first teaching frame.

This keeps the video grounded in the actual Vault demo output while making the final result editable, deterministic enough to re-render, and extensible for later demo tracks.

## Architecture

The pipeline has four small parts:

| Part | Responsibility |
| --- | --- |
| Capture target | Exposes the workflow through Make, prepares Vault, runs preflight, and invokes capture. |
| Capture script | Runs the existing demo in auto-advance mode and records a raw terminal transcript. |
| Scene builder | Converts terminal output into structured scenes with titles, commands, outputs, and presenter notes. |
| Remotion app | Renders the structured scenes into a terminal-first presentation video. |

The first video layout is **terminal-first**: the terminal capture is the main visual element, and a side panel explains "what I am doing" for the current PKI step. This prioritises command/result clarity while still making the video feel like a guided presentation.

## Components

Add a small `video/` workspace:

- `video/capture-demo.sh`
  - Runs the unattended `make demo` capture.
  - Preserves raw output for debugging.
  - Fails loudly when prerequisites are missing or preflight fails.

- `video/build-scenes.js`
  - Parses step headings such as `==== Step 3: Generate Root Certificate ====`.
  - Groups subsequent commands and outputs under each step.
  - Emits a stable JSON file for Remotion.

- `video/scene-metadata.json`
  - Stores deterministic presenter notes and teaching labels keyed by step title.
  - Lets the video narration layer improve without modifying the shell demo.

- `video/scenes/pki-demo-scenes.json`
  - Generated handoff file consumed by Remotion.
  - Treated as generated output unless explicitly sanitised for fixtures.

- `video/remotion/`
  - Remotion project that renders the terminal-first teaching frame.
  - Defines preview and render commands.

Update existing files minimally:

- `pki-demo.sh`
  - Honour an auto-advance/capture environment variable so the same script can run interactively or unattended.

- `Makefile`
  - Add targets such as `demo-video-capture`, `demo-video-preview`, and `demo-video-render`.

## Data flow

1. User runs `make demo-video-capture`.
2. The Make target verifies prerequisites and runs the existing setup/preflight path.
3. Capture invokes `pki-demo.sh` with fixed auto-advance pauses.
4. Raw terminal output is written under `video/captures/`.
5. Scene builder parses the transcript into scenes keyed by demo headings.
6. Scene builder redacts sensitive certificate material before writing generated scene JSON.
7. Scene builder enriches each scene from `video/scene-metadata.json`.
8. Remotion reads `video/scenes/pki-demo-scenes.json`.
9. Remotion renders each scene with:
   - the captured command/result transcript,
   - a current step title,
   - a presenter note panel,
   - a PKI phase indicator.

## Error handling

- Missing required tools fail before capture begins.
- Demo preflight failure stops the video workflow.
- Failed capture preserves the raw transcript for debugging.
- Generated scenes must redact private keys, Vault tokens, PEM blocks that represent private key material, and other credential-shaped values before Remotion consumes them.
- Certificate bodies may be collapsed to safe summaries unless the scene explicitly needs to teach certificate structure.
- Capture must not delete user files or broad project state.
- Remotion preview/render should fail if scene JSON is missing or malformed.

## Generated artefact policy

Generated capture and render outputs must not be committed by default:

- `video/captures/` contains raw terminal transcripts and is ignored.
- `video/scenes/pki-demo-scenes.json` is generated and ignored unless a sanitised fixture is intentionally checked in for tests.
- Remotion render outputs are ignored.
- Sanitised parser fixtures can be committed under a fixture directory when they contain no private keys, Vault tokens, or raw certificate material.

## Validation

Use lightweight checks first:

- Shell syntax checks for capture scripts when available.
- A fixture-based check for `video/build-scenes.js` that verifies step extraction.
- A low-scale Remotion still render to catch layout and runtime errors.
- One local end-to-end `make demo-video-capture` run once Vault is ready.

## Follow-on extensions

After the first slice works, the same model can support:

- `make agent-demo` for Vault Agent templating and rotation.
- `make process-demo` for application restart behaviour.
- Voiceover or subtitles generated from the scene metadata.
- Webcam picture-in-picture.
- More cinematic lifecycle animations for the PKI flow.
