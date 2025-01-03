let WasmEdgeCaseGenerators: [CodeGenerator] = [
    // メモリ境界のテスト
    CodeGenerator("WasmMemoryBoundaryTest") { b in
        b.buildTryCatchFinally(tryBody: {
            let WebAssembly = b.loadBuiltin("WebAssembly")
            let memory = b.construct(b.getProperty("Memory", of: WebAssembly), withArgs: [
                b.createObject(with: [
                    "initial": b.loadInt(1)
                ])
            ])
            
            // 境界値でのアクセス
            let view = b.construct(b.loadBuiltin("Int32Array"), withArgs: [
                b.getProperty("buffer", of: memory)
            ])
            b.callMethod("set", on: view, withArgs: [b.loadInt(65532), b.loadInt(42)])
        })
    },
    
    // 並行アクセスのテスト
    CodeGenerator("WasmConcurrentAccessTest") { b in
        b.buildTryCatchFinally(tryBody: {
            let WebAssembly = b.loadBuiltin("WebAssembly")
            let memory = b.construct(b.getProperty("Memory", of: WebAssembly), withArgs: [
                b.createObject(with: [
                    "initial": b.loadInt(1),
                    "shared": b.loadBool(true)
                ])
            ])
            
            let view = b.construct(b.loadBuiltin("Int32Array"), withArgs: [
                b.getProperty("buffer", of: memory)
            ])
            b.callMethod("set", on: view, withArgs: [b.loadInt(0), b.loadInt(42)])
        })
    }
] 