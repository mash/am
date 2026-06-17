import FoundationModels
import Foundation

// fm — a thin CLI over Apple's on-device Foundation Model.
//
//   fm [options] [prompt]
//
// The user prompt is the positional argument, or stdin if omitted. The default
// output is the completion text on stdout; --json surfaces every detail the
// framework exposes (token counts, error kind, recovery suggestion, refusal
// explanation). Exit codes give callers a machine-readable verdict without
// parsing JSON.

let WINDOW = 4096  // on-device context window (input + output), tokens

enum Exit: Int32 {
  case ok = 0
  case error = 1
  case unavailable = 3
  case contextExceeded = 4
  case guardrail = 5
  case refusal = 6
  case rateLimited = 7
  case unsupportedLanguage = 8
  case schema = 9
  case assetsUnavailable = 10
  case concurrent = 11
  case usage = 64
}

func die(_ msg: String, _ code: Exit) -> Never {
  FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
  exit(code.rawValue)
}

func emitJSON(_ obj: [String: Any]) {
  let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

struct Options {
  var system: String? = nil
  var prompt: String? = nil
  var json = false
  var temperature: Double? = nil
  var maxTokens: Int? = nil
  var greedy = false
  var seed: UInt64? = nil
  var countTokens = false
  var check = false
  var stream = false
  var batch = false
}

let HELP = """
fm — Apple on-device Foundation Model, from the command line.

USAGE:
  fm [options] [prompt]
  echo "prompt" | fm [options]

INPUT:
  [prompt]                user prompt; read from stdin if omitted
  -s, --system <text>     system instructions
      --system-file <p>   read system instructions from a file

OUTPUT:
  (default)               completion text on stdout
      --json              full structured JSON (content, tokens, error detail)
      --stream            stream completion tokens to stdout as they arrive (plain text)

BATCH:
      --batch             read NDJSON from stdin, one request per line, emit one
                          JSON result per line. Reuses the process and warmed
                          model across all requests. Each line:
                            {"prompt": "...", "system": "...", "id": "..."}
                          (system/id optional; -s/-t/-m flags apply to all lines)

GENERATION:
  -t, --temperature <f>   sampling temperature
  -m, --max-tokens <n>    maximum response tokens
      --greedy            deterministic (greedy) sampling
      --seed <n>          random-sampling seed

UTILITY:
      --count-tokens      print prompt token count vs window (\(WINDOW)); no generation
      --check             print model availability and exit (0 ok / 3 unavailable)
  -h, --help
  -V, --version

EXIT CODES:
  0 ok   1 error   3 unavailable   4 context-exceeded   5 guardrail
  6 refusal   7 rate-limited   8 unsupported-language   9 schema
  10 assets-unavailable   11 concurrent
"""

func parseArgs() -> Options {
  var o = Options()
  var positional: [String] = []
  var systemFile: String? = nil
  let args = Array(CommandLine.arguments.dropFirst())
  var i = 0
  func value(_ flag: String) -> String {
    i += 1
    guard i < args.count else { die("fm: \(flag) requires a value", .usage) }
    return args[i]
  }
  while i < args.count {
    let a = args[i]
    switch a {
    case "-h", "--help": print(HELP); exit(0)
    case "-V", "--version": print("fm 0.1.0"); exit(0)
    case "-s", "--system": o.system = value(a)
    case "--system-file": systemFile = value(a)
    case "--json": o.json = true
    case "-t", "--temperature": o.temperature = Double(value(a))
    case "-m", "--max-tokens": o.maxTokens = Int(value(a))
    case "--greedy": o.greedy = true
    case "--seed": o.seed = UInt64(value(a))
    case "--count-tokens": o.countTokens = true
    case "--check": o.check = true
    case "--stream": o.stream = true
    case "--batch": o.batch = true
    case "--": i += 1; while i < args.count { positional.append(args[i]); i += 1 }; continue
    default:
      if a.hasPrefix("-") && a != "-" { die("fm: unknown option \(a)", .usage) }
      positional.append(a)
    }
    i += 1
  }
  if let f = systemFile {
    guard let s = try? String(contentsOfFile: f, encoding: .utf8) else { die("fm: cannot read \(f)", .usage) }
    o.system = s
  }
  if let p = positional.first { o.prompt = p }
  return o
}

func readPrompt(_ o: Options) -> String {
  if let p = o.prompt { return p }
  let data = FileHandle.standardInput.readDataToEndOfFile()
  return String(data: data, encoding: .utf8) ?? ""
}

func makeOptions(_ o: Options) -> GenerationOptions {
  var sampling: GenerationOptions.SamplingMode? = nil
  if o.greedy { sampling = .greedy }
  else if let seed = o.seed { sampling = .random(top: 50, seed: seed) }
  return GenerationOptions(sampling: sampling, temperature: o.temperature, maximumResponseTokens: o.maxTokens)
}

// tokenCount is macOS 26.4+. Returns nil on older systems (best-effort).
func countTokens(_ text: String) async -> Int? {
  if #available(macOS 26.4, *) {
    return try? await SystemLanguageModel.default.tokenCount(for: text)
  }
  return nil
}

func reasonString(_ r: SystemLanguageModel.Availability.UnavailableReason) -> String {
  switch r {
  case .deviceNotEligible: return "deviceNotEligible"
  case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled"
  case .modelNotReady: return "modelNotReady"
  @unknown default: return "unknown"
  }
}

@main
struct FM {
  static func main() async {
    let o = parseArgs()

    // --- availability ---
    switch SystemLanguageModel.default.availability {
    case .available:
      if o.check {
        if o.json { emitJSON(["ok": true, "available": true]) } else { print("available") }
        exit(0)
      }
    case .unavailable(let reason):
      let r = reasonString(reason)
      if o.json { emitJSON(["ok": false, "kind": "unavailable", "reason": r]) }
      else { FileHandle.standardError.write("fm: unavailable: \(r)\n".data(using: .utf8)!) }
      exit(Exit.unavailable.rawValue)
    }

    // --- batch mode: NDJSON in/out, one process for all requests ---
    if o.batch { await runBatch(o); exit(0) }

    let prompt = readPrompt(o)
    let session = LanguageModelSession(instructions: o.system)

    // --- token counting mode ---
    if o.countTokens {
      guard let n = await countTokens(prompt) else {
        die("fm: token counting requires macOS 26.4+", .error)
      }
      if o.json { emitJSON(["ok": true, "tokens": n, "window": WINDOW, "fits": n < WINDOW]) }
      else { print("\(n)\t/ \(WINDOW)") }
      exit(0)
    }

    // --- streaming mode (plain text only; --json implies buffered) ---
    if o.stream && !o.json {
      do {
        let stream = session.streamResponse(to: prompt, options: makeOptions(o))
        var printed = 0
        for try await snapshot in stream {
          let s = snapshot.content
          if s.count > printed {
            let start = s.index(s.startIndex, offsetBy: printed)
            FileHandle.standardOutput.write(String(s[start...]).data(using: .utf8)!)
            printed = s.count
          }
        }
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        exit(0)
      } catch let e as LanguageModelSession.GenerationError {
        await reportGenerationError(e, json: false)
      } catch {
        FileHandle.standardError.write("fm: \(error)\n".data(using: .utf8)!)
        exit(Exit.error.rawValue)
      }
    }

    // --- generation (buffered) ---
    let promptTokens = await countTokens(prompt)
    do {
      let response = try await session.respond(to: prompt, options: makeOptions(o))
      if o.json {
        var out: [String: Any] = ["ok": true, "content": response.content]
        if let pt = promptTokens { out["tokens"] = ["prompt": pt, "window": WINDOW] }
        emitJSON(out)
      } else {
        FileHandle.standardOutput.write(response.content.data(using: .utf8)!)
      }
      exit(0)
    } catch let e as LanguageModelSession.GenerationError {
      await reportGenerationError(e, json: o.json)
    } catch {
      if o.json { emitJSON(["ok": false, "kind": "error", "errorDescription": "\(error)"]) }
      else { FileHandle.standardError.write("fm: \(error)\n".data(using: .utf8)!) }
      exit(Exit.error.rawValue)
    }
  }

  // Maps a GenerationError to (machine-readable kind, exit code, JSON fields).
  // Shared by single-shot and batch paths.
  static func errorInfo(_ e: LanguageModelSession.GenerationError) async -> (kind: String, code: Exit, fields: [String: Any]) {
    let kind: String
    let code: Exit
    var refusalExplanation: String? = nil
    switch e {
    case .exceededContextWindowSize: kind = "context-exceeded"; code = .contextExceeded
    case .guardrailViolation: kind = "guardrail"; code = .guardrail
    case .rateLimited: kind = "rate-limited"; code = .rateLimited
    case .unsupportedLanguageOrLocale: kind = "unsupported-language"; code = .unsupportedLanguage
    case .unsupportedGuide, .decodingFailure: kind = "schema"; code = .schema
    case .assetsUnavailable: kind = "assets-unavailable"; code = .assetsUnavailable
    case .concurrentRequests: kind = "concurrent"; code = .concurrent
    case .refusal(let refusal, _):
      kind = "refusal"; code = .refusal
      refusalExplanation = try? await refusal.explanation.content
    @unknown default: kind = "error"; code = .error
    }
    var fields: [String: Any] = [:]
    if let d = e.errorDescription { fields["errorDescription"] = d }
    if let f = e.failureReason { fields["failureReason"] = f }
    if let r = e.recoverySuggestion { fields["recoverySuggestion"] = r }
    if let x = refusalExplanation { fields["refusalExplanation"] = x }
    return (kind, code, fields)
  }

  // Reads NDJSON lines from stdin, processes each in this same process (so the
  // model is loaded once and reused), emits one JSON result per line. A bad or
  // failing line is reported and skipped; the batch never aborts midway.
  static func runBatch(_ o: Options) async {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { continue }
      guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
            let prompt = obj["prompt"] as? String else {
        emitJSON(["ok": false, "kind": "bad-input",
                  "errorDescription": "each line must be JSON with a string \"prompt\""])
        continue
      }
      var out: [String: Any] = [:]
      if let id = obj["id"] { out["id"] = id }
      let sys = (obj["system"] as? String) ?? o.system
      let session = LanguageModelSession(instructions: sys)
      do {
        let response = try await session.respond(to: prompt, options: makeOptions(o))
        out["ok"] = true
        out["content"] = response.content
        emitJSON(out)
      } catch let e as LanguageModelSession.GenerationError {
        let info = await errorInfo(e)
        out["ok"] = false
        out["kind"] = info.kind
        for (k, v) in info.fields { out[k] = v }
        emitJSON(out)
      } catch {
        out["ok"] = false
        out["kind"] = "error"
        out["errorDescription"] = "\(error)"
        emitJSON(out)
      }
    }
  }

  static func reportGenerationError(_ e: LanguageModelSession.GenerationError, json: Bool) async {
    let (kind, code, fields) = await errorInfo(e)
    if json {
      var out: [String: Any] = ["ok": false, "kind": kind]
      for (k, v) in fields { out[k] = v }
      emitJSON(out)
    } else {
      var msg = "fm: \(kind)"
      if let d = fields["errorDescription"] as? String { msg += ": \(d)" }
      if let x = fields["refusalExplanation"] as? String { msg += "\n\(x)" }
      FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    }
    exit(code.rawValue)
  }
}
