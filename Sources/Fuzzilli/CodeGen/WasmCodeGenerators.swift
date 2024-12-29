public let WasmCodeGenerators = [
    // WASMモジュールをインスタンス化するジェネレータ
    CodeGenerator("WasmInstantiateGenerator", inputs: .preferred(.object())) { b, module in
        // モジュールをインスタンス化
        let instance = b.instantiateWasmModule(module)

        // メモリを取得
        let memory = b.getWasmMemory(instance)

        // ランダムなデータを書き込む
        let offset = Int64.random(in: 0...1024)
        let data = (0..<Int.random(in: 1...32)).map { _ in UInt8.random(in: 0...255) }
        b.writeWasmMemory(memory, offset: offset, values: data)

        // エクスポートされた関数を取得して呼び出す
        let exportName = "test_func"
        let func_ = b.getWasmExport(instance, exportName)
        b.callFunction(func_, withArgs: b.randomArguments(forCalling: func_))
    },

    // WASMメモリを操作するジェネレータ
    CodeGenerator("WasmMemoryGenerator", inputs: .preferred(.object())) { b, memory in
        // ランダムなオフセットにデータを書き込む
        let offset = Int64.random(in: 0...1024)
        let data = (0..<Int.random(in: 1...32)).map { _ in UInt8.random(in: 0...255) }
        b.writeWasmMemory(memory, offset: offset, values: data)
    },

    // WASMグローバル変数を操作するジェネレータ
    CodeGenerator("WasmGlobalGenerator", inputs: .preferred(.object())) { b, instance in
        let globalName = "test_global"
        let global = b.getWasmGlobal(instance, name: globalName)

        // グローバル変数を使用
        withEqualProbability(
            {
                b.binary(global, b.loadInt(42), with: .Add)
            },
            {
                b.binary(global, b.loadInt(2), with: .Mul)
            },
            {
                b.binary(global, b.loadFloat(3.14), with: .Div)
            })
    },

    // WASMテーブルを操作するジェネレータ
    CodeGenerator("WasmTableGenerator", inputs: .preferred(.object())) { b, instance in
        let table = b.construct(
            b.getProperty("Table", of: instance),
            withArgs: [b.loadInt(10), b.loadString("anyfunc")])
        b.callMethod("grow", on: table, withArgs: [b.loadInt(1)])
    },

    // WASM構造体を操作するジェネレータ
    CodeGenerator("WasmStructGenerator", inputs: .preferred(.object())) { b, instance in
        let struct_ = b.construct(
            b.getProperty("Struct", of: instance),
            withArgs: [b.createArray(with: [b.loadString("i32")])])
        b.callMethod("set", on: struct_, withArgs: [b.loadInt(0), b.loadInt(42)])
    },

    // WASM配列を操作するジェネレータ
    CodeGenerator("WasmArrayGenerator", inputs: .preferred(.object())) { b, instance in
        let array = b.construct(
            b.getProperty("Array", of: instance),
            withArgs: [b.loadString("i32"), b.loadInt(10)])
        b.callMethod("set", on: array, withArgs: [b.loadInt(0), b.loadInt(42)])
    },
]
