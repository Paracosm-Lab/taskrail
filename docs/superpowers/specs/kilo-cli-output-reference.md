# Kilo CLI Output Format Reference

Captured 2026-06-05. Kilo CLI version 7.0.47.

## Command

```bash
kilo run --auto --format json --model "kilo/kilo-auto/free" "your prompt here"
```

`--format json` emits newline-delimited JSON events (JSON-lines) to stdout.

---

## Output Format

Each line of stdout is a standalone JSON object. Event types observed:

### `step_start`
```json
{
  "type": "step_start",
  "timestamp": 1780722661680,
  "sessionID": "ses_164a8915dffezcMcaHeKqGfPgJ",
  "part": {
    "id": "prt_...",
    "sessionID": "ses_...",
    "messageID": "msg_...",
    "type": "step-start"
  }
}
```

### `tool_use`
```json
{
  "type": "tool_use",
  "timestamp": 1780722663630,
  "sessionID": "ses_...",
  "part": {
    "type": "tool",
    "callID": "chatcmpl-tool-...",
    "tool": "write",
    "state": {
      "status": "completed",
      "input": { "filePath": "/path/to/file", "content": "..." },
      "output": "Wrote file successfully.",
      "title": "path/to/file"
    }
  }
}
```

### `text`
```json
{
  "type": "text",
  "timestamp": 1780722663664,
  "sessionID": "ses_...",
  "part": {
    "type": "text",
    "text": "\nWrote \"hello world\" to /tmp/kilo-test/hello.txt",
    "time": { "start": 1780722663662, "end": 1780722663662 }
  }
}
```

Note: There may be intermediate `text` events with empty `text` fields. The meaningful final message is in the last `text` event with non-empty `part.text` before the terminal `step_finish`.

### `step_finish`
```json
{
  "type": "step_finish",
  "timestamp": 1780722663666,
  "sessionID": "ses_...",
  "part": {
    "type": "step-finish",
    "reason": "stop",
    "cost": 0,
    "tokens": {
      "total": 29215,
      "input": 26731,
      "output": 36,
      "reasoning": 18,
      "cache": { "read": 2448, "write": 0 }
    }
  }
}
```

`reason` values observed:
- `"tool-calls"` — step ended because it made tool calls (more steps follow)
- `"stop"` — model finished, final step

---

## Parsing Strategy for KiloCliSubmitter

```ruby
def parse_json_lines(stdout)
  events = stdout.to_s.lines.filter_map do |line|
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end
  return {} if events.empty?

  session_id = events.first&.fetch("sessionID", nil)
  
  # Final message: last text event with non-empty part.text
  final_text_event = events.reverse.find do |e|
    e["type"] == "text" && e.dig("part", "text").present?
  end
  
  # Terminal step_finish has reason: "stop"
  terminal_step = events.reverse.find do |e|
    e["type"] == "step_finish" && e.dig("part", "reason") == "stop"
  end
  
  {
    "session_id" => session_id,
    "final_message" => final_text_event&.dig("part", "text")&.strip,
    "tokens" => terminal_step&.dig("part", "tokens"),
    "cost" => terminal_step&.dig("part", "cost"),
    "events" => events,
    "mode" => "json_lines"
  }.compact
end
```

`external_id` maps to `session_id` (the `sessionID` field on all events).

---

## Prompt Delivery

**Both positional arg and stdin work.**

```bash
# Positional argument
kilo run --auto --format json --model "..." "your prompt here"

# Stdin (piped)
echo "your prompt here" | kilo run --auto --format json --model "..."
```

Stdin confirmed working — `/tmp/kilo-test/hello2.txt` was created correctly when prompt was piped.

**Recommendation:** Use stdin (write to stdin like CodexCliSubmitter) to avoid `ARG_MAX` limits with long prompts. The `Open3.popen3` stdin write approach is confirmed compatible.

---

## `--agent` Flag

Agent names are user-defined in `~/.config/kilo/`. The only built-in agent observed is `ask`. There is no hardcoded `code` agent. The `--agent` flag accepts any agent name configured locally — it is optional and should not be required in the adapter.

---

## `--dir` Flag

`--dir <path>` sets the working directory for Kilo's file operations. Confirmed present in `kilo run --help`. This should be passed explicitly alongside `chdir:` in `Open3.popen3` for consistency.

---

## Deepseek Model Names

Deepseek is available via:
- `cloudflare-ai-gateway/workers-ai/@cf/deepseek-ai/deepseek-r1-distill-qwen-32b`
- `cloudflare-workers-ai/@cf/deepseek-ai/deepseek-r1-distill-qwen-32b`

Note: No `deepseek/deepseek-chat` provider — the plan's example model name needs updating. Use the full provider/model path from `kilo models`.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| non-zero | Error |
| 124 | Timeout (set by submitter, not Kilo itself) |

---

## Key Differences from Codex

| Aspect | Codex | Kilo |
|--------|-------|------|
| Output format | JSONL (has `type: "thread.started"`, `turn.completed`) | JSONL (has `step_start`, `step_finish`) |
| Session ID field | `thread_id` | `sessionID` |
| Final message location | `item.text` on `item.completed` event | `part.text` on `text` event |
| Success signal | `turn.completed` event | `step_finish` with `reason: "stop"` |
| Artifacts | In `final_message` text (structured JSON) | In `final_message` text (structured JSON) |
| Prompt delivery | stdin | stdin ✅ or positional arg |
