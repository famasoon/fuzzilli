// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Dispatch
import Foundation
import Fuzzilli

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private enum ExecutionOutcome: CustomStringConvertible {
    case succeeded
    case failed(exitCode: Int32)
    case signaled(signal: Int32)
    case timedOut
    case launchFailure(message: String)

    var isInteresting: Bool {
        switch self {
        case .succeeded:
            return false
        default:
            return true
        }
    }

    var description: String {
        switch self {
        case .succeeded:
            return "succeeded"
        case .failed(let exitCode):
            return "failed (exit code: \(exitCode))"
        case .signaled(let signal):
            return "crashed (signal: \(signal))"
        case .timedOut:
            return "timed out"
        case .launchFailure(let message):
            return "failed to launch: \(message)"
        }
    }
}

private struct ExecutionResult {
    let outcome: ExecutionOutcome
    let stdout: Data
    let stderr: Data
    let duration: TimeInterval
}

private struct FuzzConfiguration {
    let enginePath: String
    let iterations: Int
    let instructionBudget: Int
    let moduleGenerationAttempts: Int
    let timeoutInMilliseconds: Int
    let outputDirectory: URL?
    let storeAllPrograms: Bool
    let includeCommentsInHarness: Bool
}

private func printUsage(programName: String) {
    print("""
Usage:
    \(programName) --engine=<path> [options]

Options:
    --engine=path              : Path to the JavaScript engine used to execute the generated harnesses.
    --iterations=n             : Number of programs to execute (default: 100).
    --instructions=n           : Number of instructions to generate per program (default: 120).
    --moduleAttempts=n         : Attempts per iteration to obtain a program that contains Wasm (default: 50).
    --timeout=ms               : Execution timeout for each program in milliseconds (default: 1000).
    --output=path              : Directory in which interesting programs will be stored.
    --storeAll                 : Store every generated program instead of only interesting ones.
    --includeComments          : Include FuzzIL comments in the generated JavaScript harness.
    --help                     : Print this help text.
""")
}

private func parseConfiguration(from arguments: Arguments) -> FuzzConfiguration? {
    if arguments["--help"] != nil || arguments["-h"] != nil {
        printUsage(programName: arguments.programName)
        exit(0)
    }

    if arguments.numPositionalArguments != 0 {
        print("Unexpected positional arguments. See --help for usage information.")
        return nil
    }

    guard let engine = arguments["--engine"], !engine.isEmpty else {
        print("Please provide a JavaScript engine path with --engine=<path>.")
        return nil
    }

    guard FileManager.default.isExecutableFile(atPath: engine) else {
        print("Provided engine path \(engine) is not executable or does not exist.")
        return nil
    }

    let iterations = arguments.int(for: "--iterations") ?? 100
    if iterations <= 0 {
        print("--iterations must be a positive integer.")
        return nil
    }

    let instructionBudget = arguments.int(for: "--instructions") ?? 120
    if instructionBudget <= 0 {
        print("--instructions must be a positive integer.")
        return nil
    }

    let attempts = arguments.int(for: "--moduleAttempts") ?? 50
    if attempts <= 0 {
        print("--moduleAttempts must be a positive integer.")
        return nil
    }

    let timeout = arguments.int(for: "--timeout") ?? 1000
    if timeout <= 0 {
        print("--timeout must be a positive integer.")
        return nil
    }

    var outputDirectory: URL? = nil
    if let path = arguments["--output"], !path.isEmpty {
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
    }

    let storeAll = arguments.has("--storeAll")
    let includeComments = arguments.has("--includeComments")

    return FuzzConfiguration(enginePath: engine,
                              iterations: iterations,
                              instructionBudget: instructionBudget,
                              moduleGenerationAttempts: attempts,
                              timeoutInMilliseconds: timeout,
                              outputDirectory: outputDirectory,
                              storeAllPrograms: storeAll,
                              includeCommentsInHarness: includeComments)
}

private func ensureOutputDirectoryExists(_ url: URL) -> Bool {
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return true
    } catch {
        print("Failed to create output directory at \(url.path): \(error)")
        return false
    }
}

private func generateWasmProgram(using fuzzer: Fuzzer,
                                 instructionBudget: Int,
                                 attempts: Int) -> Program? {
    for _ in 0..<attempts {
        var program: Program?
        fuzzer.sync {
            let builder = fuzzer.makeBuilder()
            builder.buildPrefix()
            builder.build(n: instructionBudget, by: .generating)
            program = builder.finalize()
        }

        if let candidate = program, candidate.containsWasm {
            return candidate
        }
    }
    return nil
}

private func liftToJavaScript(_ program: Program,
                              lifter: JavaScriptLifter,
                              includeComments: Bool) -> String {
    var options: LiftingOptions = []
    if includeComments {
        options.insert(.includeComments)
    }
    return lifter.lift(program, withOptions: options)
}

private func write(_ data: Data, to url: URL) {
    do {
        try data.write(to: url)
    } catch {
        print("Warning: failed to write \(url.lastPathComponent): \(error)")
    }
}

private func write(_ string: String, to url: URL) {
    do {
        try string.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        print("Warning: failed to write \(url.lastPathComponent): \(error)")
    }
}

private func storeProgram(_ program: Program,
                          javascript: String,
                          result: ExecutionResult,
                          iteration: Int,
                          in directory: URL) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: Date())
    let baseName = "case_\(String(format: "%05d", iteration))_\(timestamp)"
    let caseDirectory = directory.appendingPathComponent(baseName, isDirectory: true)

    do {
        try FileManager.default.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
    } catch {
        print("Warning: failed to create \(caseDirectory.path): \(error)")
        return
    }

    write(javascript, to: caseDirectory.appendingPathComponent("program.js"))

    do {
        let data = try program.asProtobuf().serializedData()
        write(data, to: caseDirectory.appendingPathComponent("program.fzil"))
    } catch {
        print("Warning: failed to serialize program: \(error)")
    }

    let stdoutString = String(data: result.stdout, encoding: .utf8) ?? "<non-UTF8 data>"
    let stderrString = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF8 data>"
    write(stdoutString, to: caseDirectory.appendingPathComponent("stdout.txt"))
    write(stderrString, to: caseDirectory.appendingPathComponent("stderr.txt"))

    var metadataLines = ["outcome: \(result.outcome.description)"]
    metadataLines.append(String(format: "duration_ms: %.2f", result.duration * 1000))
    write(metadataLines.joined(separator: "\n"), to: caseDirectory.appendingPathComponent("metadata.txt"))
}

private func runScript(_ script: String,
                       withEngine enginePath: String,
                       timeoutInMilliseconds timeout: Int) -> ExecutionResult {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("wasm_fuzz_\(UUID().uuidString).js")
    do {
        try script.write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
        return ExecutionResult(outcome: .launchFailure(message: "failed to write temporary harness: \(error)"),
                               stdout: Data(), stderr: Data(), duration: 0)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: enginePath)
    process.arguments = [tempURL.path]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let start = Date()
    do {
        try process.run()
    } catch {
        try? FileManager.default.removeItem(at: tempURL)
        return ExecutionResult(outcome: .launchFailure(message: "failed to spawn engine: \(error)"),
                               stdout: Data(), stderr: Data(), duration: 0)
    }

    let waitGroup = DispatchGroup()
    waitGroup.enter()
    DispatchQueue.global().async {
        process.waitUntilExit()
        waitGroup.leave()
    }

    var didTimeout = false
    if waitGroup.wait(timeout: .now() + .milliseconds(timeout)) == .timedOut {
        didTimeout = true
        if process.isRunning {
            process.terminate()
        }
        if process.isRunning {
            process.interrupt()
        }
        if process.isRunning {
            let pid = process.processIdentifier
            if pid != 0 {
                kill(pid, SIGKILL)
            }
        }
        waitGroup.wait()
    }

    let duration = Date().timeIntervalSince(start)
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    try? FileManager.default.removeItem(at: tempURL)

    if didTimeout {
        return ExecutionResult(outcome: .timedOut, stdout: stdoutData, stderr: stderrData, duration: duration)
    }

    switch process.terminationReason {
    case .exit:
        if process.terminationStatus == 0 {
            return ExecutionResult(outcome: .succeeded, stdout: stdoutData, stderr: stderrData, duration: duration)
        } else {
            return ExecutionResult(outcome: .failed(exitCode: process.terminationStatus), stdout: stdoutData, stderr: stderrData, duration: duration)
        }
    case .uncaughtSignal:
        return ExecutionResult(outcome: .signaled(signal: process.terminationStatus), stdout: stdoutData, stderr: stderrData, duration: duration)
    @unknown default:
        return ExecutionResult(outcome: .failed(exitCode: process.terminationStatus), stdout: stdoutData, stderr: stderrData, duration: duration)
    }
}

private func runFuzzingSession(with configuration: FuzzConfiguration) {
    if let outputDirectory = configuration.outputDirectory {
        guard ensureOutputDirectoryExists(outputDirectory) else {
            return
        }
    }

    let fuzzerQueue = DispatchQueue(label: "WasmFuzzTool.Fuzzer")
    let fuzzer = makeMockFuzzer(config: Configuration(logLevel: .warning,
                                                     enableInspection: true,
                                                     isWasmEnabled: true),
                                queue: fuzzerQueue)

    let lifter = JavaScriptLifter(prefix: "",
                                  suffix: "",
                                  ecmaVersion: .es6,
                                  environment: fuzzer.environment,
                                  alwaysEmitVariables: configuration.includeCommentsInHarness)

    print("Starting Wasm fuzzing session against \(configuration.enginePath)")
    print("Iterations: \(configuration.iterations), instruction budget: \(configuration.instructionBudget), timeout: \(configuration.timeoutInMilliseconds) ms")

    var interestingPrograms = 0

    for iteration in 1...configuration.iterations {
        guard let program = generateWasmProgram(using: fuzzer,
                                                instructionBudget: configuration.instructionBudget,
                                                attempts: configuration.moduleGenerationAttempts) else {
            print("[Iteration \(iteration)] Failed to generate a program containing Wasm instructions.")
            continue
        }

        let script = liftToJavaScript(program, lifter: lifter, includeComments: configuration.includeCommentsInHarness)
        let result = runScript(script, withEngine: configuration.enginePath, timeoutInMilliseconds: configuration.timeoutInMilliseconds)

        print("[Iteration \(iteration)] \(result.outcome.description) (\(String(format: "%.2f", result.duration * 1000)) ms)")

        let shouldStore = configuration.storeAllPrograms || result.outcome.isInteresting
        if shouldStore, let outputDirectory = configuration.outputDirectory {
            storeProgram(program,
                         javascript: script,
                         result: result,
                         iteration: iteration,
                         in: outputDirectory)
        }

        if result.outcome.isInteresting {
            interestingPrograms += 1
        }
    }

    print("Fuzzing session finished. Interesting programs found: \(interestingPrograms)")
}

let arguments = Arguments.parse(from: CommandLine.arguments)

guard let configuration = parseConfiguration(from: arguments) else {
    exit(-1)
}

runFuzzingSession(with: configuration)
