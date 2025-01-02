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

/// WebAssembly関連の操作をJavaScriptにリフトするためのヘルパークラス
public class WasmLifter {
    /// WebAssemblyモジュールのインスタンス化をリフトする
    public static func liftInstantiateWasm(wasmBinary: Expression, imports: [Expression]) -> Expression {
        let importArgs = imports.isEmpty ? "" : ", { imports: {\(imports.map { $0.text }.joined(separator: ", "))} }"
        return CallExpression.new() + "WebAssembly.instantiate(" + wasmBinary + importArgs + ")"
    }
    
    /// WebAssemblyエクスポートの取得をリフトする
    public static func liftGetWasmExport(instance: Expression, exportName: String) -> Expression {
        return MemberExpression.new() + instance + ".exports['" + exportName + "']"
    }
    
    /// WebAssemblyメモリの取得をリフトする
    public static func liftGetWasmMemory(instance: Expression, memoryIndex: Int64) -> Expression {
        return MemberExpression.new() + instance + ".memory[" + String(memoryIndex) + "]"
    }
    
    /// WebAssemblyメモリへの書き込みをリフトする
    public static func liftWriteWasmMemory(memory: Expression, offset: Int64, bytes: [UInt8]) -> Expression {
        let bytesStr = bytes.map { String($0) }.joined(separator: ",")
        let arrayExpr = "new Uint8Array(" + memory.text + ".buffer)"
        return CallExpression.new() + arrayExpr + ".set([" + bytesStr + "], " + String(offset) + ")"
    }
    
    /// WebAssemblyグローバル変数の取得をリフトする
    public static func liftGetWasmGlobal(instance: Expression, globalName: String) -> Expression {
        return MemberExpression.new() + instance + ".globals['" + globalName + "']"
    }
} 