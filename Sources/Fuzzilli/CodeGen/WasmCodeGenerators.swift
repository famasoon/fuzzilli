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
    },
    
    CodeGenerator("WasmAddFunctionGenerator") { b in
        b.buildTryCatchFinally(tryBody: {
            let WebAssembly = b.loadBuiltin("WebAssembly")
            
            // 加算関数を含むWasmバイナリを作成
            let wasmBytes = b.createArray(with: [
                // マジックナンバーとバージョン
                b.loadInt(0x00), b.loadInt(0x61), b.loadInt(0x73), b.loadInt(0x6d),
                b.loadInt(0x01), b.loadInt(0x00), b.loadInt(0x00), b.loadInt(0x00),
                
                // タイプセクション
                b.loadInt(0x01), b.loadInt(0x07), b.loadInt(0x01),
                b.loadInt(0x60), b.loadInt(0x02), b.loadInt(0x7f), b.loadInt(0x7f),
                b.loadInt(0x01), b.loadInt(0x7f),
                
                // 関数セクション
                b.loadInt(0x03), b.loadInt(0x02), b.loadInt(0x01), b.loadInt(0x00),
                
                // エクスポートセクション
                b.loadInt(0x07), b.loadInt(0x07), b.loadInt(0x01),
                b.loadInt(0x03), b.loadInt(0x61), b.loadInt(0x64), b.loadInt(0x64),
                b.loadInt(0x00), b.loadInt(0x00),
                
                // コードセクション
                b.loadInt(0x0a), b.loadInt(0x09), b.loadInt(0x01),
                b.loadInt(0x07), b.loadInt(0x00),
                b.loadInt(0x20), b.loadInt(0x00),
                b.loadInt(0x20), b.loadInt(0x01),
                b.loadInt(0x6a), b.loadInt(0x0b)
            ])
            
            // モジュールの検証と作成
            b.callMethod("validate", on: WebAssembly, withArgs: [wasmBytes])
            let module = b.construct(b.getProperty("Module", of: WebAssembly), withArgs: [wasmBytes])
            
            // インスタンス化
            let instance = b.construct(b.getProperty("Instance", of: WebAssembly), withArgs: [module])
            
            // 関数のテスト
            let add = b.getProperty("add", of: b.getProperty("exports", of: instance))
            b.callFunction(add, withArgs: [b.loadInt(1), b.loadInt(2)])
            
        }, catchBody: { error in
            b.loadUndefined()
        })
    },
    
    CodeGenerator("WasmTableAndGlobalGenerator") { b in
        b.buildTryCatchFinally(tryBody: {
            let WebAssembly = b.loadBuiltin("WebAssembly")
            
            // テーブルの作成
            let tableDesc = b.createObject(with: [
                "element": b.loadString("anyfunc"),
                "initial": b.loadInt(1)
            ])
            let table = b.construct(b.getProperty("Table", of: WebAssembly), withArgs: [tableDesc])
            
            // グローバル変数の作成
            let globalDesc = b.createObject(with: [
                "value": b.loadString("i32"),
                "mutable": b.loadBool(true)
            ])
            let global = b.construct(b.getProperty("Global", of: WebAssembly), withArgs: [globalDesc, b.loadInt(42)])
            
            // 値の取得と設定
            b.callMethod("set", on: global, withArgs: [b.loadInt(100)])
            b.callMethod("get", on: global)
            
        }, catchBody: { error in
            b.loadUndefined()
        })
    }
]
