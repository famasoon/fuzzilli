// Copyright 2020 Google LLC
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


/// Builtin program templates to target specific types of bugs.
public let ProgramTemplates = [
    ProgramTemplate("Codegen100") { b in
        b.buildPrefix()
        // Go wild.
        b.build(n: 100)
    },

    ProgramTemplate("Codegen50") { b in
        b.buildPrefix()
        // Go (a little less) wild.
        b.build(n: 50)
    },

    ProgramTemplate("JIT1Function") { b in
        let smallCodeBlockSize = 5
        let numIterations = 100

        // Start with a random prefix and some random code.
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate a larger function
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 30)
            b.doReturn(b.randomVariable())
        }

        // Generate some random instructions now
        b.build(n: smallCodeBlockSize)

        // trigger JIT
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))

        // maybe trigger recompilation
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)

        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    ProgramTemplate("JIT2Functions") { b in
        let smallCodeBlockSize = 5
        let numIterations = 100

        // Start with a random prefix and some random code.
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate a larger function
        let f1 = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 20)
            b.doReturn(b.randomVariable())
        }

        // Generate a second larger function
        let f2 = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 20)
            b.doReturn(b.randomVariable())
        }

        // Generate some random instructions now
        b.build(n: smallCodeBlockSize)

        // trigger JIT for first function
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        }

        // trigger JIT for second function
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)

        b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))

        // maybe trigger recompilation
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        }

        // maybe trigger recompilation
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)

        b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
    },

    ProgramTemplate("JITTrickyFunction") { b in
        // This templates generates functions that behave differently in some of the iterations.
        // The functions will essentially look like this:
        //
        //     function f(arg1, arg2, i) {
        //         if (i == N) {
        //             // do stuff
        //         }
        //         // do stuff
        //     }
        //
        // Or like this:
        //
        //     function f(arg1, arg2, i) {
        //         if (i % N == 0) {
        //             // do stuff
        //         }
        //         // do stuff
        //     }
        //
        let smallCodeBlockSize = 5
        let numIterations = 100

        // Helper function to generate code that only runs during some of the iterations.
        func buildCodeThatRunsInOnlySomeIterations(iterationCount: Variable) {
            // Decide when to run the code.
            let cond: Variable
            if probability(0.5) {
                // Run the code in one specific iteration
                let selectedIteration = withEqualProbability({
                    // Prefer to perform the action during one of the last iterations
                    assert(numIterations > 10)
                    return Int.random(in: (numIterations - 10)..<numIterations)
                }, {
                    return Int.random(in: 0..<numIterations)
                })
                cond = b.compare(iterationCount, with: b.loadInt(Int64(selectedIteration)), using: .equal)
            } else {
                // Run the code every nth iteration
                let modulus = b.loadInt(chooseUniform(from: [2, 5, 10, 25]))
                let remainder = b.binary(iterationCount, modulus, with: .Mod)
                cond = b.compare(remainder, with: b.loadInt(0), using: .equal)
            }

            // We hide the cond variable since it's probably not very useful for subsequent code to use it.
            // The other variables (e.g. remainder) are maybe a bit more useful, so we leave them visible.
            b.hide(cond)

            // Now build the code, wrapped in an if block.
            b.buildIf(cond) {
                b.build(n: 5)
            }
        }

        // Start with a random prefix and some random code.
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate the target function.
        // Here we simply prepend the iteration count to randomly generated parameters.
        // This way, the signature is still valid even if the last parameter is a rest parameter.
        let baseParams = b.randomParameters().parameterTypes
        let actualParams = [.integer] + baseParams
        let f = b.buildPlainFunction(with: .parameters(actualParams)) { args in
            // Generate a few "prefix" instructions
            b.build(n: smallCodeBlockSize)

            // Build code that will only be executed in some of the iterations.
            buildCodeThatRunsInOnlySomeIterations(iterationCount: args[0])

            // Build the main body.
            b.build(n: 20)
            b.doReturn(b.randomVariable())
        }

        // Generate some more random instructions.
        b.build(n: smallCodeBlockSize)

        // Call the function repeatedly to trigger JIT compilation, then perform additional steps in the final iteration. Do this 2 times to potentially trigger recompilation.
        b.buildRepeatLoop(n: 2) {
            b.buildRepeatLoop(n: numIterations) { i in
                buildCodeThatRunsInOnlySomeIterations(iterationCount: i)
                var args = [i] + b.randomArguments(forCallingFunctionWithParameters: baseParams)
                b.callFunction(f, withArgs: args)
            }
        }

        // Call the function again, this time with potentially different arguments.
        b.buildRepeatLoop(n: numIterations) { i in
            buildCodeThatRunsInOnlySomeIterations(iterationCount: i)
            var args = [i] + b.randomArguments(forCallingFunctionWithParameters: baseParams)
            b.callFunction(f, withArgs: args)
        }
    },

    ProgramTemplate("JSONFuzzer") { b in
        b.buildPrefix()

        // Create some random values that will be JSON.stringified below.
        b.build(n: 25)

        // Generate random JSON payloads by stringifying random values
        let JSON = b.loadBuiltin("JSON")
        var jsonPayloads = [Variable]()
        for _ in 0..<Int.random(in: 1...5) {
            let json = b.callMethod("stringify", on: JSON, withArgs: [b.randomVariable()])
            jsonPayloads.append(json)
        }

        // Optionally mutate (some of) the json string
        let mutateJson = b.buildPlainFunction(with: .parameters(.string)) { args in
            let json = args[0]

            // Helper function to pick a random index in the json string.
            let randIndex = b.buildPlainFunction(with: .parameters(.integer)) { args in
                let max = args[0]
                let Math = b.loadBuiltin("Math")
                // We "hardcode" the random value here (instead of calling `Math.random()` in JS) so that testcases behave deterministically.
                var random = b.loadFloat(Double.random(in: 0..<1))
                random = b.binary(random, max, with: .Mul)
                random = b.callMethod("floor", on: Math, withArgs: [random])
                b.doReturn(random)
            }

            // Flip a random character of the JSON string:
            // Select a random index at which to flip the character.
            let String = b.loadBuiltin("String")
            let length = b.getProperty("length", of: json)
            let index = b.callFunction(randIndex, withArgs: [length])

            // Save the substrings before and after the character that will be changed.
            let zero = b.loadInt(0)
            let prefix = b.callMethod("substring", on: json, withArgs: [zero, index])
            let indexPlusOne = b.binary(index, b.loadInt(1), with: .Add)
            let suffix = b.callMethod("substring", on: json, withArgs: [indexPlusOne])

            // Extract the original char code, xor it with a random 7-bit number, then construct the new character value.
            let originalCharCode = b.callMethod("charCodeAt", on: json, withArgs: [index])
            let newCharCode = b.binary(originalCharCode, b.loadInt(Int64.random(in: 1..<128)), with: .Xor)
            let newChar = b.callMethod("fromCharCode", on: String, withArgs: [newCharCode])

            // And finally construct the mutated string.
            let tmp = b.binary(prefix, newChar, with: .Add)
            let newJson = b.binary(tmp, suffix, with: .Add)
            b.doReturn(newJson)
        }

        for (i, json) in jsonPayloads.enumerated() {
            // Performing (essentially binary) mutations on the JSON content will mostly end up fuzzing the JSON parser, not the JSON object
            // building logic (which, in optimized JS engines, is likely much more complex). So perform these mutations somewhat rarely.
            guard probability(0.25) else { continue }
            jsonPayloads[i] = b.callFunction(mutateJson, withArgs: [json])
        }

        // Parse the JSON payloads back into JS objects.
        // Instead of shuffling the jsonString array, we generate random indices so that there is a chance that the same string is parsed multiple times.
        for _ in 0..<(jsonPayloads.count * 2) {
            let json = chooseUniform(from: jsonPayloads)
            // Parsing will throw if the input is invalid, so add guards
            b.callMethod("parse", on: JSON, withArgs: [json], guard: true)
        }

        // Generate some more random code to (hopefully) use the parsed JSON in some interesting way.
        b.build(n: 25)
    },

    ProgramTemplate("WasmFuzzer") { b in
        b.buildPrefix()

        // WASMモジュールを作成
        let wasmModule = b.loadBuiltin("WebAssembly")
        let moduleBytes = b.loadInt(Int64.random(in: 0...1000000))
        let module = b.construct(wasmModule, withArgs: [moduleBytes])

        // モジュールをインスタンス化
        let instance = b.instantiateWasmModule(module)

        // メモリにアクセス
        let memory = b.getWasmMemory(instance)
        
        // ランダムなデータを書き込む
        for _ in 0..<5 {
            let offset = Int64.random(in: 0..<1024)
            let data = (0..<Int.random(in: 1...32)).map { _ in UInt8.random(in: 0...255) }
            b.writeWasmMemory(memory, offset: offset, values: data)
        }

        // エクスポートされた関数を呼び出す
        let exportNames = ["test_func1", "test_func2", "test_func3"]
        for name in exportNames {
            let func_ = b.getWasmExport(instance, name)
            b.callFunction(func_, withArgs: b.randomArguments(forCalling: func_))
        }

        // グローバル変数を操作
        let global = b.getWasmGlobal(instance, name: "test_global")
        b.binary(global, b.loadInt(42), with: .Add)
    },

    ProgramTemplate("ComplexWasmFuzzer") { b in 
        b.buildPrefix()

        // WASMモジュールを作成
        let wasmModule = b.loadBuiltin("WebAssembly")
        let moduleBytes = b.loadInt(Int64.random(in: 0...1000000))
        let module = b.construct(wasmModule, withArgs: [moduleBytes])

        // インポートオブジェクトを作成
        let importObj = b.buildObjectLiteral { obj in
            // env名前空間を作成
            let env = b.buildObjectLiteral { envObj in
                // コールバック関数を追加
                envObj.addMethod("callback", with: .parameters(n: 2)) { args in
                    b.buildRecursive(n: 5)
                    b.doReturn(args[0])
                }
                
                // メモリを追加
                let memory = b.construct(b.getProperty("Memory", of: wasmModule), 
                                      withArgs: [b.loadInt(1)])
                envObj.addProperty("memory", as: memory)
                
                // テーブルを追加
                let table = b.construct(b.getProperty("Table", of: wasmModule),
                                     withArgs: [b.loadInt(10), b.loadString("anyfunc")])
                envObj.addProperty("table", as: table)
            }
            obj.addProperty("env", as: env)
        }

        // モジュールをインスタンス化
        let instance = b.instantiateWasmModule(module, withImports: [importObj])

        // メモリ操作のテスト
        let memory = b.getWasmMemory(instance)
        
        // 複数のメモリ領域に対して操作を実行
        let regions = [(0, 128), (256, 384), (512, 640), (768, 896)]
        for (start, end) in regions {
            // ランダムなデータを書き込む
            let offset = Int64.random(in: Int64(start)...Int64(end))
            let data = (0..<Int.random(in: 16...64)).map { _ in UInt8.random(in: 0...255) }
            b.writeWasmMemory(memory, offset: offset, values: data)
            
            // メモリ操作の間に関数呼び出しを挟む
            if probability(0.5) {
                let func_ = b.getWasmExport(instance, "test_func")
                b.callFunction(func_, withArgs: [b.loadInt(offset)])
            }
        }

        // 複数のグローバル変数を操作
        let globalNames = ["g1", "g2", "g3", "accumulator"]
        for name in globalNames {
            let global = b.getWasmGlobal(instance, name: name)
            
            // グローバル変数に対して様々な演算を実行
            withEqualProbability({
                b.binary(global, b.loadInt(42), with: .Add)
            }, {
                b.binary(global, b.loadInt(2), with: .Mul)
            }, {
                b.binary(global, b.loadFloat(3.14), with: .Div)
            })
        }

        // エクスポートされた関数を様々なパターンで呼び出す
        let exportNames = ["add", "sub", "mul", "div", "mod"]
        for name in exportNames {
            let func_ = b.getWasmExport(instance, name)
            
            // 関数呼び出しのバリエーション
            withEqualProbability({
                // 通常の呼び出し
                b.callFunction(func_, withArgs: [b.loadInt(42), b.loadInt(7)])
            }, {
                // エラーが発生しそうな引数での呼び出し
                b.callFunction(func_, withArgs: [b.loadInt(0), b.loadInt(0)])
            }, {
                // 大きな値での呼び出し
                b.callFunction(func_, withArgs: [b.loadInt(Int64.max), b.loadInt(Int64.min)])
            })
        }

        // 条件分岐を含むテスト
        let condition = b.compare(b.getWasmGlobal(instance, name: "flag"), with: b.loadInt(1), using: .equal)
        b.buildIfElse(condition, 
            ifBody: {
                // trueの場合の処理
                let func1 = b.getWasmExport(instance, "true_path")
                b.callFunction(func1, withArgs: [b.loadInt(1)])
            },
            elseBody: {
                // falseの場合の処理
                let func2 = b.getWasmExport(instance, "false_path")
                b.callFunction(func2, withArgs: [b.loadInt(0)])
            }
        )

        // ループ内でのWASM関数呼び出し
        b.buildRepeatLoop(n: 10) { i in
            let func_ = b.getWasmExport(instance, "loop_func")
            b.callFunction(func_, withArgs: [i])
            
            // メモリ操作も組み合わせる
            // 固定のオフセットを使用
            let data = [UInt8(Int.random(in: 0...255))]
            b.writeWasmMemory(memory, offset: Int64(8), values: data)  // 固定オフセットを使用
        }
    },
]
