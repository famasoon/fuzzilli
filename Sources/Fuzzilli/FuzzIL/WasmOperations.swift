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

import Foundation

// WASMモジュールのインスタンス化
public class InstantiateWasm: Operation {
  let numImports: Int
  
  override var opcode: Opcode { .instantiateWasm(self) }
  
  init(numImports: Int) {
    self.numImports = numImports
    super.init(
      numInputs: numImports + 1,
      numOutputs: 1,
      numInnerOutputs: 0,
      attributes: [.isPure, .isCall],
      requiredContext: .javascript
    )
  }
}

// WASMエクスポートの取得
public class GetWasmExport: Operation {
  let exportName: String

  init(exportName: String) {
    self.exportName = exportName
    super.init(
      numInputs: 1,
      numOutputs: 1,
      attributes: [.isPure],
      requiredContext: .javascript
    )
  }
  
  override var opcode: Opcode { .getWasmExport(self) }
}

// WASMメモリーの取得
public class GetWasmMemory: Operation {
  let memoryIndex: Int

  init(memoryIndex: Int) {
    self.memoryIndex = memoryIndex
    super.init(
      numInputs: 1,
      numOutputs: 1,
      attributes: [.isPure],
      requiredContext: .javascript
    )
  }
  
  override var opcode: Opcode { .getWasmMemory(self) }
}

// WASMメモリーへの書き込み
public class WriteWasmMemory: Operation {
  let offset: Int64
  let bytes: [UInt8]

  init(offset: Int64, bytes: [UInt8]) {
    self.offset = offset
    self.bytes = bytes
    super.init(
      numInputs: 1,
      numOutputs: 0,
      attributes: [],
      requiredContext: .javascript
    )
  }
  
  override var opcode: Opcode { .writeWasmMemory(self) }
}

// WASMグローバル変数の取得
public class GetWasmGlobal: Operation {
  let globalName: String

  init(globalName: String) {
    self.globalName = globalName
    super.init(
      numInputs: 1,
      numOutputs: 1,
      attributes: [.isPure],
      requiredContext: .javascript
    )
  }
  
  override var opcode: Opcode { .getWasmGlobal(self) }
}
