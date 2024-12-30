public let WasmCodeGenerators = [
    CodeGenerator("BasicWasmGenerator") { b in
        b.buildTryCatchFinally(tryBody: {
            let WebAssembly = b.loadBuiltin("WebAssembly")
            
            // 基本的なバイナリデータを作成
            let wasmBytes = b.createArray(with: [
                b.loadInt(0x00), b.loadInt(0x61), b.loadInt(0x73), b.loadInt(0x6d),  // マジックナンバー
                b.loadInt(0x01), b.loadInt(0x00), b.loadInt(0x00), b.loadInt(0x00)   // バージョン
            ])
            
            // モジュールの検証
            b.callMethod("validate", on: WebAssembly, withArgs: [wasmBytes])
            
            // モジュールの作成
            let module = b.construct(b.getProperty("Module", of: WebAssembly), withArgs: [wasmBytes])
            
            // インスタンス化
            let instance = b.construct(b.getProperty("Instance", of: WebAssembly), withArgs: [module])
            
        }, catchBody: { error in
            b.loadUndefined()
        })
    },
    
    CodeGenerator("WasmMemoryGenerator") { b in
        b.buildTryCatchFinally(tryBody: {
            let WebAssembly = b.loadBuiltin("WebAssembly")
            
            // メモリの作成
            let memoryDesc = b.createObject(with: [
                "initial": b.loadInt(1)
            ])
            let memory = b.construct(b.getProperty("Memory", of: WebAssembly), withArgs: [memoryDesc])
            
            // メモリの操作
            b.callMethod("grow", on: memory, withArgs: [b.loadInt(1)])
            
        }, catchBody: { error in
            b.loadUndefined()
        })
    }
]
