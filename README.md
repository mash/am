# fm

Run Apple's on-device Foundation Model from the command line. Pipe in a prompt, get a completion back. No API key, no billing, no network: the device runs everything.

## Requirements

- macOS 26 or later, Apple Silicon
- Apple Intelligence enabled (check with `fm check`)
- Xcode or the Swift toolchain to build (`fm tokens` needs macOS 26.4)

## Install

```sh
brew install mash/tap/fm
```

From source:

```sh
git clone https://github.com/mash/fm
cd fm
make install                  # installs to /usr/local (needs sudo)
make install PREFIX=$HOME/.local   # or a sudo-free prefix on your PATH
```

## Usage

```sh
# from stdin
echo "Explain a monad in one sentence." | fm

# from an argument
fm "What is 2+2? Answer with just the number."

# with system instructions
fm -s "You are a terse cook." "How do I keep pasta from sticking?"

# full detail as JSON, for programs
echo "Name one primary color." | fm --json
# {"content":"Red ...","ok":true,"tokens":{"prompt":14,"window":4096}}

# stream tokens as they arrive
fm --stream "Write a haiku about the sea."

# interactive session that keeps context
fm repl
```

Generation is the default. The other operations are subcommands: `repl`, `check`, `tokens`, and `batch`. A subcommand is only recognized as the first argument; otherwise the first argument is treated as the prompt.

```sh
fm [prompt]            # generate (default; prompt from arg or stdin)
fm repl                # interactive REPL (requires a terminal)
fm check               # model availability
fm tokens [prompt]     # prompt token count vs window
fm batch               # NDJSON in/out
```

Running `fm` with no prompt in a terminal prints help and exits 64; with an empty pipe it exits 64 with `fm: empty prompt`.

### REPL

`fm repl` opens an interactive session that keeps conversational context across turns and streams each reply as it arrives. It requires a terminal. Type `exit`, `quit`, or press Ctrl-D to end; `/reset` clears the context.

```sh
fm repl
# fm — interactive. Ctrl-D or `exit` to quit, `/reset` to clear context.
# > Name a primary color. One word.
# Red.
# > And another?
# Blue.
```

### Options

```
fm [options] [prompt]
fm <command> [options] [prompt]

Commands:
  repl                    interactive session; keeps context, streams replies
  check                   print model availability (exit 0 if ready, 3 if not)
  tokens [prompt]         print the prompt's token count against the window (4096); macOS 26.4+
  batch                   read NDJSON from stdin, one request per line, one JSON result per line

Input:
  [prompt]                user prompt; read from stdin if omitted
  -s, --system <text>     system instructions
      --system-file <p>   read system instructions from a file

Output:
  (default)               completion text on stdout
      --json              full JSON: content, tokens, and error detail
      --stream            stream tokens to stdout as they arrive (plain text)

Generation:
  -t, --temperature <f>   sampling temperature
  -m, --max-tokens <n>    maximum response tokens
      --greedy            deterministic (greedy) sampling
      --seed <n>          random-sampling seed

  -h, --help / -V, --version
```

### Batch

`fm batch` reads NDJSON from stdin, runs one request per line, and prints one JSON result per line. It reuses a single process and a warmed model across every request, so a large run pays process startup and model load only once.

```sh
printf '%s\n' \
  '{"id":"a","prompt":"Name a primary color. One word."}' \
  '{"id":"b","prompt":"2+2? Number only.","system":"You are terse."}' | fm batch
# {"content":"Red.","id":"a","ok":true}
# {"content":"4","id":"b","ok":true}
```

Each line takes a string `prompt` and optional `system` and `id`. The `-s`, `-t`, and `-m` flags apply to every line. A bad or failing line reports an error, and the batch continues.

### Exit codes

`fm` returns the result kind as an exit code, so a caller can branch on it without parsing JSON.

| code | meaning |
|---|---|
| 0 | ok |
| 1 | error |
| 3 | unavailable (reason: `deviceNotEligible`, `appleIntelligenceNotEnabled`, or `modelNotReady`) |
| 4 | context exceeded (input is over the 4096-token window) |
| 5 | guardrail (input or output tripped a safety guardrail) |
| 6 | refusal (the model declined; `--json` carries `refusalExplanation`) |
| 7 | rate limited |
| 8 | unsupported language |
| 9 | schema |
| 10 | assets unavailable (model not downloaded) |
| 11 | concurrent request |

## Limits

- The context window holds 4096 tokens, input and output combined. Larger input exits with code 4. Measure it first with `fm tokens`.
- The on-device model is a shared, serial resource. Parallel requests — across processes or sessions — do not raise throughput.
- The model leans toward English. To pin the output language, say so in `-s`.

## Calling fm from other programs

`fm` follows a plain stdin/stdout/exit-code contract, so any language can run it as a subprocess. In Go:

```go
cmd := exec.Command("fm", "-s", systemPrompt, "--json")
cmd.Stdin = strings.NewReader(userPrompt)
out, _ := cmd.Output()
// branch on the exit code; read detail from --json
```

For many requests, prefer `fm batch`: write one JSON object per line to the process, read one result per line.
