# Design: Demo Terminal Cleanup

## Problem

The demo scripts still contain decorative non-ASCII terminal styling, mainly box-drawing headers and the `➜` prompt glyph. After the first cleanup pass removed emoji-style icons, these remaining characters still make the demos feel more stylized than desired.

## Goals

- Make demo-visible terminal output fully ASCII.
- Keep the demos readable and professional.
- Preserve the current command flow, colors, pacing, and behavior.
- Limit the change to output that users actually see during demo runs.

## Non-Goals

- No logic changes to PKI setup, certificate rotation, or process supervision.
- No repo-wide text normalization outside demo-visible paths.
- No removal of ANSI colors in this pass.

## Chosen Approach

Use a targeted fully-ASCII cleanup in demo-visible output only.

This keeps the scope focused on presentation while avoiding unnecessary churn in unrelated files. It also preserves the current demo structure, which reduces the risk of breaking walkthroughs or helper flows.

## Scope

The cleanup applies to demo-visible scripts and helper output that appears during demo runs:

- `pki-demo.sh`
- `agent-pki-demo.sh`
- `demo-process-supervisor.sh`
- `watch-rotation.sh`
- `vault-init.sh`
- `quick-start.sh`
- `ensure-agent-credentials.sh`
- `setup-agent-credentials.sh`
- `vault-agent-config/myapp.sh`

## Design Details

### Headings and framing

- Replace box-drawing title frames with plain ASCII headings.
- Use simple section separators such as `==== Step 3: Generate Root Certificate ====` or an equivalent single-line ASCII format.
- Keep blank-line spacing so the demos remain easy to scan in a terminal.

### Prompt and labels

- Replace the `➜` demo prompt glyph with `$`.
- Use plain ASCII bullets such as `-`.
- Use neutral status labels such as `OK:`, `WARNING:`, `ERROR:`, and `INFO:` where status emphasis is helpful.

### Runtime output compatibility

- Keep ANSI colors where they already exist.
- Update any grep or log-filter expressions that currently depend on the old stylized output so the process-supervisor demo still surfaces the right events.

## Validation

- Run `bash -n` on each edited shell script.
- Run a targeted non-ASCII scan across the files in scope.
- Spot-check diffs to confirm the change is presentation-only.
- If needed after the edit, manually run `make demo` or `make agent-demo` to confirm the updated formatting still reads well.

## Risks and Mitigations

- Log-monitoring filters could miss renamed lines.
  - Mitigation: update the filter patterns alongside the output text changes.
- Simpler headings may slightly change line wrapping.
  - Mitigation: keep headings short and visually consistent.

## Success Criteria

- Demo-visible output in scope is fully ASCII.
- The demo prompt uses `$`.
- Demo flow and behavior remain unchanged apart from presentation cleanup.
