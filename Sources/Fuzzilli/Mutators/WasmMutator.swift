// Copyright 2023 Google LLC
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

/// WebAssembly関連の操作をミューテートするミューテータ
public class WasmMutator: BaseInstructionMutator {
    private var deadCodeAnalyzer = DeadCodeAnalyzer()
    
    public init() {
        super.init(maxSimultaneousMutations: defaultMaxSimultaneousMutations)
    }
    
    public override func beginMutation(of program: Program) {
        deadCodeAnalyzer = DeadCodeAnalyzer()
    }
    
    public override func canMutate(_ instr: Instruction) -> Bool {
        deadCodeAnalyzer.analyze(instr)
        
        // デッドコード内でない場合のみミューテート可能
        guard !deadCodeAnalyzer.currentlyInDeadCode else { return false }
        
        // WebAssembly関連の命令のみをミューテート
        switch instr.op.opcode {
        case .instantiateWasm,
             .getWasmExport,
             .getWasmMemory,
             .writeWasmMemory,
             .getWasmGlobal:
            return true
        default:
            return false
        }
    }
    
    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        switch instr.op.opcode {
        case .instantiateWasm:
            mutateInstantiateWasm(instr, b)
        case .getWasmExport:
            mutateGetWasmExport(instr, b)
        case .getWasmMemory:
            mutateGetWasmMemory(instr, b)
        case .writeWasmMemory:
            mutateWriteWasmMemory(instr, b)
        case .getWasmGlobal:
            mutateGetWasmGlobal(instr, b)
        default:
            b.adopt(instr)
        }
    }
    
    private func mutateInstantiateWasm(_ instr: Instruction, _ b: ProgramBuilder) {
        // インポートオブジェクトの追加/削除をランダムに行う
        let wasmModule = b.adopt(instr.input(0))
        let numImports = Int.random(in: 0...3)
        let imports = (0..<numImports).map { _ in b.randomVariable() }
        b.instantiateWasm(wasmModule, imports: imports)
    }
    
    private func mutateGetWasmExport(_ instr: Instruction, _ b: ProgramBuilder) {
        let instance = b.adopt(instr.input(0))
        let exportNames = ["memory", "table", "global", "func", "main", "start", "add", "sub", "mul"]
        let newExportName = chooseUniform(from: exportNames)
        b.getWasmExport(instance, newExportName)
    }
    
    private func mutateGetWasmMemory(_ instr: Instruction, _ b: ProgramBuilder) {
        let instance = b.adopt(instr.input(0))
        let memoryIndex = Int(Int64.random(in: 0...3))
        b.getWasmMemory(instance, index: memoryIndex)
    }
    
    private func mutateWriteWasmMemory(_ instr: Instruction, _ b: ProgramBuilder) {
        let memory = b.adopt(instr.input(0))
        let newOffset = Int64.random(in: 0...1024)
        let numBytes = Int.random(in: 1...16)
        let newBytes = (0..<numBytes).map { _ in UInt8.random(in: 0...255) }
        b.writeWasmMemory(memory, offset: newOffset, values: newBytes)
    }
    
    private func mutateGetWasmGlobal(_ instr: Instruction, _ b: ProgramBuilder) {
        let instance = b.adopt(instr.input(0))
        let globalNames = ["g0", "g1", "g2", "global0", "global1", "value", "result"]
        let newGlobalName = chooseUniform(from: globalNames)
        b.getWasmGlobal(instance, name: newGlobalName)
    }
} 