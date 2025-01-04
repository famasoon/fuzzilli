private func generateWasmSIMDModule(operations: [String]) -> [UInt8] {
    // 簡単なWASMバイナリを生成
    return [
        0x00, 0x61, 0x73, 0x6d,  // マジックナンバー
        0x01, 0x00, 0x00, 0x00,  // バージョン
        // ... 最小限のWASMモジュール
    ]
}

let WasmGenerators1Array: [CodeGenerator] = [
    // メモリ操作のテスト
    CodeGenerator("WasmMemoryFuzzer") { b in
        b.buildTryCatchFinally(
            tryBody: {
                let WebAssembly = b.loadBuiltin("WebAssembly")

                // より安全なメモリ設定
                let memoryDesc = b.createObject(with: [
                    "initial": b.loadInt(1),
                    "maximum": b.loadInt(2),  // maximumを設定して制限を追加
                    "shared": b.loadBool(false),  // 明示的に共有を無効化
                ])

                let memory = b.construct(
                    b.getProperty("Memory", of: WebAssembly), withArgs: [memoryDesc])

                // Int32Arrayのみを使用して安定性を向上
                let view = b.construct(
                    b.loadBuiltin("Int32Array"),
                    withArgs: [
                        b.getProperty("buffer", of: memory)
                    ])

                // より安全な範囲でのメモリアクセス
                let offset = b.loadInt(Int64.random(in: 0...10))  // 小さな範囲に制限
                let value = b.loadInt(42)  // 固定値を使用

                // メモリ操作の前に範囲チェック
                let condition = b.compare(offset, with: b.loadInt(10), using: .lessThan)
                b.buildIfElse(
                    condition,
                    ifBody: {
                        b.callMethod("set", on: view, withArgs: [offset, value])
                    },
                    elseBody: {
                        // 範囲外の場合は何もしない
                        b.loadUndefined()
                    }
                )

            },
            catchBody: { error in
                b.loadUndefined()
            })
    },

    // SIMDテスト
    CodeGenerator("WasmSIMDFuzzer") { b in
        b.buildTryCatchFinally(
            tryBody: {
                let WebAssembly = b.loadBuiltin("WebAssembly")

                // 基本的なSIMDモジュールのバイナリ
                let wasmBytes = b.createArray(with: [
                    // マジックナンバーとバージョン
                    b.loadInt(0x00), b.loadInt(0x61), b.loadInt(0x73), b.loadInt(0x6d),
                    b.loadInt(0x01), b.loadInt(0x00), b.loadInt(0x00), b.loadInt(0x00),

                    // タイプセクション
                    b.loadInt(0x01), b.loadInt(0x07), b.loadInt(0x01),
                    b.loadInt(0x60), b.loadInt(0x02), b.loadInt(0x7b), b.loadInt(0x7b),
                    b.loadInt(0x01), b.loadInt(0x7b),

                    // 関数セクション
                    b.loadInt(0x03), b.loadInt(0x02), b.loadInt(0x01), b.loadInt(0x00),

                    // エクスポートセクション
                    b.loadInt(0x07), b.loadInt(0x07), b.loadInt(0x01),
                    b.loadInt(0x03), b.loadInt(3), b.loadString("add"),
                    b.loadInt(0x00), b.loadInt(0x00),
                ])

                // モジュールの検証
                b.callMethod("validate", on: WebAssembly, withArgs: [wasmBytes])

                // モジュールの作成とインスタンス化
                let module = b.construct(
                    b.getProperty("Module", of: WebAssembly), withArgs: [wasmBytes])
                let instance = b.construct(
                    b.getProperty("Instance", of: WebAssembly), withArgs: [module])

                // エクスポートされた関数の呼び出し
                let exports = b.getProperty("exports", of: instance)
                let add = b.getProperty("add", of: exports)
                b.callFunction(add, withArgs: [b.loadInt(1), b.loadInt(2)])

            },
            catchBody: { error in
                b.loadUndefined()
            })
    },
]
