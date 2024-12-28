import Foundation

// WASMモジュールのインスタンス化
public class InstantiateWasm: Operation {
  let numImports: Int

  init(numImports: Int) {
    self.numImports = numImports
    super.init(
      numInputs: 1 + numImports,
      numOutputs: 1,
      requiredContext: .javascript)
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
      requiredContext: .javascript)
  }
}

// WASMメモリーの取得
public class GetWasmMemory: Operation {
  let memoryIndex: Int

  init(memoryIndex: Int) {
    self.memoryIndex = memoryIndex
    super.init(
      numInputs: 1,
      numOutputs: 1,
      requiredContext: .javascript)
  }
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
      requiredContext: .javascript)
  }
}

// WASMグローバル変数の取得
public class GetWasmGlobal: Operation {
  let globalName: String

  init(globalName: String) {
    self.globalName = globalName
    super.init(
      numInputs: 1,
      numOutputs: 1,
      requiredContext: .javascript)
  }
}
