let WasmEdgeCaseGenerators: [CodeGenerator] = [
    // メモリ境界のテスト
    CodeGenerator("WasmMemoryBoundaryTest") { b in
        let memory = b.construct(b.getProperty("Memory", of: b.loadBuiltin("WebAssembly")), withArgs: [
            b.createObject(with: [
                "initial": b.loadInt(1)
            ])
        ])
        b.writeWasmMemory(memory, offset: 65535, values: [1, 2, 3, 4])
    },
    
    // 並行アクセスのテスト
    CodeGenerator("WasmConcurrentAccessTest") { b in
        let sharedMemory = b.construct(b.getProperty("Memory", of: b.loadBuiltin("WebAssembly")), withArgs: [
            b.createObject(with: [
                "initial": b.loadInt(1),
                "shared": b.loadBool(true)
            ])
        ])
        b.buildRepeatLoop(n: 4) { _ in
            b.writeWasmMemory(sharedMemory, offset: Int64.random(in: 0...1024), values: [42])
        }
    },
    
    // 型変換のテスト
    CodeGenerator("WasmTypeConversionTest") { b in
        let memory = b.construct(b.getProperty("Memory", of: b.loadBuiltin("WebAssembly")), withArgs: [
            b.createObject(with: ["initial": b.loadInt(1)])
        ])
        b.writeWasmMemory(memory, offset: 0, values: [42])
    }
] 