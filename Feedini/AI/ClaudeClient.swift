import Foundation

/// One call of the `claude` CLI in print mode with a JSON schema.
struct ClaudeRequest: Sendable {
    var model: String
    var effort: String
    var systemPrompt: String
    /// The JSON schema of `structured_output`.
    var schema: String
    /// The payload, written to stdin.
    var input: Data
    var timeout: Duration = .seconds(120)
}

extension ClaudeRequest {
    /// A request whose payload is encoded as JSON.
    init(model: String, effort: String, systemPrompt: String, schema: String, payload: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        // Encoding plain strings, numbers and arrays can't fail.
        self.init(
            model: model, effort: effort, systemPrompt: systemPrompt, schema: schema,
            input: (try? encoder.encode(payload)) ?? Data())
    }
}

/// Time and cost of a call, as the CLI reports them.
struct ClaudeCallStats: Sendable, Equatable {
    var model: String
    var durationMs: Int
    var costUSD: Double
}

enum ClaudeError: Error, Sendable, Equatable {
    case notFound
    case launchFailed(String)
    case timedOut
    /// The CLI exited without an envelope on stdout.
    case exitStatus(Int32, String)
    /// The envelope isn't the JSON the CLI is expected to print.
    case invalidEnvelope
    /// The CLI reported an error (`is_error`), e.g. an API or authentication error.
    case failed(String)
    /// The envelope has no `structured_output` object.
    case noStructuredOutput(String)
    /// `structured_output` doesn't match the expected shape.
    case invalidOutput(String)

    /// For the user (Settings → AI, status line).
    var message: String {
        switch self {
        case .notFound: "claude not found"
        case .launchFailed(let reason): "claude couldn't be started: \(reason)"
        case .timedOut: "claude didn't answer in time"
        case .exitStatus(let status, let stderr):
            stderr.isEmpty ? "claude exited with status \(status)" : "claude exited with status \(status): \(stderr)"
        case .invalidEnvelope: "claude printed an unexpected answer"
        case .failed(let reason): reason
        case .noStructuredOutput(let result):
            result.isEmpty ? "claude gave no structured answer" : "claude gave no structured answer: \(result)"
        case .invalidOutput(let reason): "claude's answer has an unexpected shape: \(reason)"
        }
    }

    /// Worth trying again later (as opposed to a setup problem).
    var isTransient: Bool {
        switch self {
        case .notFound, .launchFailed: false
        default: true
        }
    }
}

/// Calls the `claude` CLI: no tools, safe mode, no saved session, the payload on stdin and the answer as structured
/// output. The content of articles is data; with no tools, a prompt injection in a feed can't do anything.
struct ClaudeClient: Sendable {
    static let userPrompt = "Process the input."

    var runner: any CommandRunning = ProcessRunner()
    /// Where `claude` is; looked up on every call, so installing it or changing Settings needs no restart.
    var locate: @Sendable () -> URL?

    static func arguments(for request: ClaudeRequest) -> [String] {
        [
            "-p", "--model", request.model, "--effort", request.effort, "--system-prompt", request.systemPrompt,
            "--safe-mode", "--tools", "", "--no-session-persistence", "--output-format", "json", "--json-schema",
            request.schema, userPrompt,
        ]
    }

    func run<Output: Decodable>(
        _ request: ClaudeRequest, as type: Output.Type
    ) async throws(ClaudeError) -> (
        Output, ClaudeCallStats
    ) {
        guard let executable = locate() else { throw .notFound }
        let output: ProcessOutput
        do {
            output = try await runner.run(
                executable, arguments: Self.arguments(for: request), input: request.input, timeout: request.timeout)
        } catch ProcessRunnerError.timedOut {
            throw .timedOut
        } catch ProcessRunnerError.launchFailed(let reason) {
            throw .launchFailed(reason)
        } catch {
            throw .failed(error.localizedDescription)
        }
        return try Self.parse(output, model: request.model, as: type)
    }

    static func parse<Output: Decodable>(
        _ output: ProcessOutput, model: String, as type: Output.Type
    )
        throws(ClaudeError) -> (Output, ClaudeCallStats)
    {
        guard !output.stdout.isEmpty else {
            throw .exitStatus(output.exitStatus, excerpt(output.stderr))
        }
        guard let object = try? JSONSerialization.jsonObject(with: output.stdout) as? [String: Any],
            object["type"] as? String == "result"
        else {
            if output.exitStatus != 0 {
                throw .exitStatus(output.exitStatus, excerpt(output.stderr.isEmpty ? output.stdout : output.stderr))
            }
            throw .invalidEnvelope
        }
        let result = object["result"] as? String ?? ""
        if object["is_error"] as? Bool == true {
            let subtype = object["subtype"] as? String ?? "error"
            throw .failed(result.isEmpty ? "claude reported an error (\(subtype))" : excerpt(Data(result.utf8)))
        }
        guard let structured = object["structured_output"] as? [String: Any],
            let data = try? JSONSerialization.data(withJSONObject: structured)
        else {
            throw .noStructuredOutput(excerpt(Data(result.utf8)))
        }
        let decoded: Output
        do {
            decoded = try JSONDecoder().decode(Output.self, from: data)
        } catch {
            throw .invalidOutput(String(describing: error))
        }
        let stats = ClaudeCallStats(
            model: model, durationMs: object["duration_ms"] as? Int ?? 0,
            costUSD: object["total_cost_usd"] as? Double ?? 0)
        return (decoded, stats)
    }

    /// The first line of a message, at most 300 characters.
    private static func excerpt(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let line = text.split(separator: "\n").first.map(String.init) ?? ""
        return line.count > 300 ? String(line.prefix(300)) + "…" : line
    }
}
