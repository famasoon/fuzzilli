// Copyright 2019 Google LLC
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

import Fuzzilli

fileprivate let ForceJITCompilationThroughLoopGenerator = CodeGenerator("ForceJITCompilationThroughLoopGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let ForceTurboFanCompilationGenerator = CodeGenerator("ForceTurboFanCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeFunctionOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
}

fileprivate let ForceMaglevCompilationGenerator = CodeGenerator("ForceMaglevCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeMaglevOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
}

fileprivate let TurbofanVerifyTypeGenerator = CodeGenerator("TurbofanVerifyTypeGenerator", inputs: .one) { b, v in
    b.eval("%VerifyType(%@)", with: [v])
}

fileprivate let WorkerGenerator = RecursiveCodeGenerator("WorkerGenerator") { b in
    let workerSignature = Signature(withParameterCount: Int.random(in: 0...3))

    // TODO(cffsmith): currently Fuzzilli does not know that this code is sent
    // to another worker as a string. This has the consequence that we might
    // use variables inside the worker that are defined in a different scope
    // and as such they are not accessible / undefined. To fix this we should
    // define an Operation attribute that tells Fuzzilli to ignore variables
    // defined in outer scopes.
    let workerFunction = b.buildPlainFunction(with: .parameters(workerSignature.parameters)) { args in
        let this = b.loadThis()

        // Generate a random onmessage handler for incoming messages.
        let onmessageFunction = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.buildRecursive(block: 1, of: 2)
        }
        b.setProperty("onmessage", of: this, to: onmessageFunction)

        b.buildRecursive(block: 2, of: 2)
    }
    let workerConstructor = b.loadBuiltin("Worker")

    let functionString = b.loadString("function")
    let argumentsArray = b.createArray(with: b.randomArguments(forCalling: workerFunction))

    let configObject = b.createObject(with: ["type": functionString, "arguments": argumentsArray])

    let worker = b.construct(workerConstructor, withArgs: [workerFunction, configObject])
    // Fuzzilli can now use the worker.
}

// Insert random GC calls throughout our code.
fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
    let gc = b.loadBuiltin("gc")

    // Do minor GCs more frequently.
    let type = b.loadString(probability(0.25) ? "major" : "minor")
    // If the execution type is 'async', gc() returns a Promise, we currently
    // do not really handle other than typing the return of gc to .undefined |
    // .jsPromise. One could either chain a .then or create two wrapper
    // functions that are differently typed such that fuzzilli always knows
    // what the type of the return value is.
    let execution = b.loadString(probability(0.5) ? "sync" : "async")
    b.callFunction(gc, withArgs: [b.createObject(with: ["type": type, "execution": execution])])
}

fileprivate let WasmStructGenerator = CodeGenerator("WasmStructGenerator") { b in
    b.buildTryCatchFinally(tryBody: {
        // より複雑なWASM構造体を生成
        let wasmModule = b.loadBuiltin("WebAssembly")
        let moduleBytes = b.createArray(with: [
            // マジックナンバーとバージョン
            b.loadInt(0x00), b.loadInt(0x61), b.loadInt(0x73), b.loadInt(0x6d),
            b.loadInt(0x01), b.loadInt(0x00), b.loadInt(0x00), b.loadInt(0x00),
            // 構造体定義を含むセクション
            b.loadInt(0x05), b.loadInt(0x03), b.loadInt(0x01), 
            b.loadInt(0x7f), b.loadInt(0x7e)
        ])
        
        b.callMethod("validate", on: wasmModule, withArgs: [moduleBytes])
        let module = b.construct(b.getProperty("Module", of: wasmModule), withArgs: [moduleBytes])
        b.construct(b.getProperty("Instance", of: wasmModule), withArgs: [module])
    }, catchBody: { error in
        b.loadUndefined()
    })
}

fileprivate let WasmArrayGenerator = CodeGenerator("WasmArrayGenerator") { b in
    b.eval("%WasmArray()", hasOutput: true)
}

fileprivate let WasmMemoryGenerator = CodeGenerator("WasmMemoryGenerator") { b in
    b.buildTryCatchFinally(tryBody: {
        let wasmMemory = b.loadBuiltin("WebAssembly.Memory")
        let memoryDesc = b.createObject(with: [
            "initial": b.loadInt(1),
            "maximum": b.loadInt(10),
            "shared": b.loadBool(probability(0.2))  // 時々共有メモリを使用
        ])
        let memory = b.construct(wasmMemory, withArgs: [memoryDesc])
        
        // 異なる型付き配列でのアクセスをテスト
        if probability(0.5) {
            let viewTypes = ["Int8Array", "Int16Array", "Int32Array", "Float32Array", "Float64Array"]
            let viewType = chooseUniform(from: viewTypes)
            let view = b.construct(b.loadBuiltin(viewType), 
                                 withArgs: [b.getProperty("buffer", of: memory)])
            b.callMethod("set", on: view, withArgs: [b.loadInt(0), b.loadInt(42)])
        }
    }, catchBody: { error in
        b.loadUndefined()
    })
}

fileprivate let WasmTableGenerator = CodeGenerator("WasmTableGenerator") { b in
    let wasmTable = b.loadBuiltin("WebAssembly.Table")
    let tableDesc = b.createObject(with: [
        "element": b.loadString("anyfunc"),
        "initial": b.loadInt(1),
        "maximum": b.loadInt(10)
    ])
    b.construct(wasmTable, withArgs: [tableDesc])
}

fileprivate let WasmGlobalGenerator = CodeGenerator("WasmGlobalGenerator") { b in
    b.eval("%WasmGlobal()", hasOutput: true)
}

fileprivate let MapTransitionFuzzer = ProgramTemplate("MapTransitionFuzzer") { b in
    // This template is meant to stress the v8 Map transition mechanisms.
    // Basically, it generates a bunch of CreateObject, GetProperty, SetProperty, FunctionDefinition,
    // and CallFunction operations operating on a small set of objects and property names.

    let propertyNames = b.fuzzer.environment.customProperties
    assert(Set(propertyNames).isDisjoint(with: b.fuzzer.environment.customMethods))

    // Use this as base object type. For one, this ensures that the initial map is stable.
    // Moreover, this guarantees that when querying for this type, we will receive one of
    // the objects we created and not e.g. a function (which is also an object).
    assert(propertyNames.contains("a"))
    let objType = ILType.object(withProperties: ["a"])

    // Helper function to pick random properties and values.
    func randomProperties(in b: ProgramBuilder) -> ([String], [Variable]) {
        if !b.hasVisibleVariables {
            // Use integer values if there are no visible variables, which should be a decent fallback.
            b.loadInt(b.randomInt())
        }

        var properties = ["a"]
        var values = [b.randomVariable()]
        for _ in 0..<3 {
            let property = chooseUniform(from: propertyNames)
            guard !properties.contains(property) else { continue }
            properties.append(property)
            values.append(b.randomVariable())
        }
        assert(Set(properties).count == values.count)
        return (properties, values)
    }

    // Temporarily overwrite the active code generators with the following generators...
    let primitiveValueGenerator = ValueGenerator("PrimitiveValue") { b, n in
        for _ in 0..<n {
            // These should roughly correspond to the supported property representations of the engine.
            withEqualProbability({
                b.loadInt(b.randomInt())
            }, {
                b.loadFloat(b.randomFloat())
            }, {
                b.loadString(b.randomString())
            })
        }
    }
    let createObjectGenerator = ValueGenerator("CreateObject") { b, n in
        for _ in 0..<n {
            let (properties, values) = randomProperties(in: b)
            let obj = b.createObject(with: Dictionary(uniqueKeysWithValues: zip(properties, values)))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectMakerGenerator = ValueGenerator("ObjectMaker") { b, n in
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            let (properties, values) = randomProperties(in: b)
            let o = b.createObject(with: Dictionary(uniqueKeysWithValues: zip(properties, values)))
            b.doReturn(o)
        }
        for _ in 0..<n {
            let obj = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectConstructorGenerator = ValueGenerator("ObjectConstructor") { b, n in
        let c = b.buildConstructor(with: b.randomParameters()) { args in
            let this = args[0]
            let (properties, values) = randomProperties(in: b)
            for (p, v) in zip(properties, values) {
                b.setProperty(p, of: this, to: v)
            }
        }
        for _ in 0..<n {
            let obj = b.construct(c, withArgs: b.randomArguments(forCalling: c))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectClassGenerator = ValueGenerator("ObjectClassGenerator") { b, n in
        let superclass = b.hasVisibleVariables && probability(0.5) ? b.randomVariable(ofType: .constructor()) : nil
        let (properties, values) = randomProperties(in: b)
        let cls = b.buildClassDefinition(withSuperclass: superclass) { cls in
            for (p, v) in zip(properties, values) {
                cls.addInstanceProperty(p, value: v)
            }
        }
        for _ in 0..<n {
            let obj = b.construct(cls)
            assert(b.type(of: obj).Is(objType))
        }
    }
    let propertyLoadGenerator = CodeGenerator("PropertyLoad", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        b.getProperty(chooseUniform(from: propertyNames), of: obj)
    }
    let propertyStoreGenerator = CodeGenerator("PropertyStore", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        let numProperties = Int.random(in: 1...3)
        for _ in 0..<numProperties {
            b.setProperty(chooseUniform(from: propertyNames), of: obj, to: b.randomVariable())
        }
    }
    let propertyConfigureGenerator = CodeGenerator("PropertyConfigure", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        b.configureProperty(chooseUniform(from: propertyNames), of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randomVariable()))
    }
    let functionDefinitionGenerator = RecursiveCodeGenerator("FunctionDefinition") { b in
        // We use either a randomly generated signature or a fixed on that ensures we use our object type frequently.
        var parameters = b.randomParameters()
        let haveVisibleObjects = b.visibleVariables.contains(where: { b.type(of: $0).Is(objType) })
        if probability(0.5) && haveVisibleObjects {
            parameters = .parameters(.plain(objType), .plain(objType), .anything, .anything)
        }

        let f = b.buildPlainFunction(with: parameters) { params in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }

        for _ in 0..<3 {
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }
    }
    let functionCallGenerator = CodeGenerator("FunctionCall", inputs: .required(.function())) { b, f in
        assert(b.type(of: f).Is(.function()))
        let rval = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    }
    let constructorCallGenerator = CodeGenerator("ConstructorCall", inputs: .required(.constructor())) { b, c in
        assert(b.type(of: c).Is(.constructor()))
        let rval = b.construct(c, withArgs: b.randomArguments(forCalling: c))
     }
    let functionJitCallGenerator = CodeGenerator("FunctionJitCall", inputs: .required(.function())) { b, f in
        assert(b.type(of: f).Is(.function()))
        let args = b.randomArguments(forCalling: f)
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f, withArgs: args)
        }
    }

    let prevCodeGenerators = b.fuzzer.codeGenerators
    b.fuzzer.setCodeGenerators(WeightedList<CodeGenerator>([
        (primitiveValueGenerator,     2),
        (createObjectGenerator,       1),
        (objectMakerGenerator,        1),
        (objectConstructorGenerator,  1),
        (objectClassGenerator,        1),

        (propertyStoreGenerator,      10),
        (propertyLoadGenerator,       10),
        (propertyConfigureGenerator,  5),
        (functionDefinitionGenerator, 2),
        (functionCallGenerator,       3),
        (constructorCallGenerator,    2),
        (functionJitCallGenerator,    2)
    ]))

    // ... run some of the ValueGenerators to create some initial objects ...
    b.buildPrefix()
    // ... and generate a bunch of code.
    b.build(n: 100, by: .generating)

    // Now, restore the previous code generators and generate some more code.
    b.fuzzer.setCodeGenerators(prevCodeGenerators)
    b.build(n: 10)

    // Finally, run HeapObjectVerify on all our generated objects (that are still in scope).
    for obj in b.visibleVariables where b.type(of: obj).Is(objType) {
        b.eval("%HeapObjectVerify(%@)", with: [obj])
    }
}

fileprivate let ValueSerializerFuzzer = ProgramTemplate("ValueSerializerFuzzer") { b in
    b.buildPrefix()

    // Create some random values that can be serialized below.
    b.build(n: 50)

    // Load necessary builtins
    let d8 = b.loadBuiltin("d8")
    let serializer = b.getProperty("serializer", of: d8)
    let Uint8Array = b.loadBuiltin("Uint8Array")

    // Serialize a random object
    let content = b.callMethod("serialize", on: serializer, withArgs: [b.randomVariable()])
    let u8 = b.construct(Uint8Array, withArgs: [content])

    // Choose a random byte to change
    let index = Int64.random(in: 0..<100)

    // Either flip or replace the byte
    let newByte: Variable
    if probability(0.5) {
        let bit = b.loadInt(1 << Int.random(in: 0..<8))
        let oldByte = b.getElement(index, of: u8)
        newByte = b.binary(oldByte, bit, with: .Xor)
    } else {
        newByte = b.loadInt(Int64.random(in: 0..<256))
    }
    b.setElement(index, of: u8, to: newByte)

    // Deserialize the resulting buffer
    let _ = b.callMethod("deserialize", on: serializer, withArgs: [content])

    // Generate some more random code to (hopefully) use the deserialized objects in some interesting way.
    b.build(n: 10)
}

// This template fuzzes the RegExp engine.
// It finds bugs like: crbug.com/1437346 and crbug.com/1439691.
fileprivate let RegExpFuzzer = ProgramTemplate("RegExpFuzzer") { b in
    // Taken from: https://source.chromium.org/chromium/chromium/src/+/refs/heads/main:v8/test/fuzzer/regexp-builtins.cc;l=212;drc=a61b95c63b0b75c1cfe872d9c8cdf927c226046e
    let twoByteSubjectString = "f\\uD83D\\uDCA9ba\\u2603"

    let replacementCandidates = [
      "'X'",
      "'$1$2$3'",
      "'$$$&$`$\\'$1'",
      "() => 'X'",
      "(arg0, arg1, arg2, arg3, arg4) => arg0 + arg1 + arg2 + arg3 + arg4",
      "() => 42"
    ]

    let lastIndices = [
      "undefined",  "-1",         "0",
      "1",          "2",          "3",
      "4",          "5",          "6",
      "7",          "8",          "9",
      "50",         "4294967296", "2147483647",
      "2147483648", "NaN",        "Not a Number"
    ]

    let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
        let (pattern, flags) = b.randomRegExpPatternAndFlags()
        let regExpVar = b.loadRegExp(pattern, flags)

        let lastIndex = chooseUniform(from: lastIndices)
        let lastIndexString = b.loadString(lastIndex)

        b.setProperty("lastIndex", of: regExpVar, to: lastIndexString)

        let subjectVar: Variable

        if probability(0.1) {
            subjectVar = b.loadString(twoByteSubjectString)
        } else {
            subjectVar = b.loadString(b.randomString())
        }

        let resultVar = b.loadNull()

        b.buildTryCatchFinally(tryBody: {
            let symbol = b.loadBuiltin("Symbol")
            withEqualProbability({
                let res = b.callMethod("exec", on: regExpVar, withArgs: [subjectVar])
                b.reassign(resultVar, to: res)
            }, {
                let prop = b.getProperty("match", of: symbol)
                let res = b.callComputedMethod(prop, on: regExpVar, withArgs: [subjectVar])
                b.reassign(resultVar, to: res)
            }, {
                let prop = b.getProperty("replace", of: symbol)
                let replacement = withEqualProbability({
                    b.loadString(b.randomString())
                }, {
                    b.loadString(chooseUniform(from: replacementCandidates))
                })
                let res = b.callComputedMethod(prop, on: regExpVar, withArgs: [subjectVar, replacement])
                b.reassign(resultVar, to: res)
            }, {
                let prop = b.getProperty("search", of: symbol)
                let res = b.callComputedMethod(prop, on: regExpVar, withArgs: [subjectVar])
                b.reassign(resultVar, to: res)
            }, {
                let prop = b.getProperty("split", of: symbol)
                let randomSplitLimit = withEqualProbability({
                    "undefined"
                }, {
                    "'not a number'"
                }, {
                    String(b.randomInt())
                })
                let limit = b.loadString(randomSplitLimit)
                let res = b.callComputedMethod(symbol, on: regExpVar, withArgs: [subjectVar, limit])
                b.reassign(resultVar, to: res)
            }, {
                let res = b.callMethod("test", on: regExpVar, withArgs: [subjectVar])
                b.reassign(resultVar, to: res)
            })
        }, catchBody: { _ in
        })

        b.build(n: 7)

        b.doReturn(resultVar)
    }

    b.eval("%SetForceSlowPath(false)");
    // compile the regexp once
    b.callFunction(f)
    let resFast = b.callFunction(f)
    b.eval("%SetForceSlowPath(true)");
    let resSlow = b.callFunction(f)
    b.eval("%SetForceSlowPath(false)");

    b.build(n: 15)
}

fileprivate let WasmInstantiateGenerator = CodeGenerator("WasmInstantiateGenerator") { b in
    let wasmModule = b.loadBuiltin("WebAssembly.Module")
    let wasmInstance = b.loadBuiltin("WebAssembly.Instance")
    
    // 最小限のWASMモジュールのバイナリデータを作成
    let arrayConstructor = b.loadBuiltin("Uint8Array")
    let wasmBytes = b.createArray(with: [
        b.loadInt(0x00), b.loadInt(0x61), b.loadInt(0x73), b.loadInt(0x6d),  // magic
        b.loadInt(0x01), b.loadInt(0x00), b.loadInt(0x00), b.loadInt(0x00),  // version
    ])
    let wasmBinary = b.construct(arrayConstructor, withArgs: [wasmBytes])
    
    let module = b.construct(wasmModule, withArgs: [wasmBinary])
    b.construct(wasmInstance, withArgs: [module])
}

// Maglev最適化のテスト用ジェネレータ
fileprivate let MaglevOptimizationGenerator = CodeGenerator("MaglevOptimizationGenerator") { b in 
    let f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
        // 型推論を促すコード
        b.buildIfElse(b.compare(args[0], with: args[1], using: .equal),
            ifBody: {
                b.binary(args[0], b.loadInt(42), with: .Add)
            },
            elseBody: {
                b.binary(args[1], b.loadFloat(3.14), with: .Mul)
            }
        )
    }

    // Maglevコンパイルを強制
    b.eval("%PrepareFunctionForOptimization(%@)", with: [f])
    for _ in 0..<3 {
        b.callFunction(f, withArgs: [b.loadInt(1), b.loadInt(2)])
    }
    b.eval("%OptimizeMaglevOnNextCall(%@)", with: [f])
    b.callFunction(f, withArgs: [b.loadInt(1), b.loadInt(2)])
}

// TurboFanの型検証を強化
fileprivate let TurbofanTypeVerifierGenerator = CodeGenerator("TurbofanTypeVerifierGenerator") { b in
    let f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
        // 型変換を含むコード
        let num = b.binary(args[0], b.loadInt(100), with: .Add)
        let str = b.callMethod("toString", on: num, withArgs: [])
        b.callMethod("charAt", on: str, withArgs: [b.loadInt(0)])
    }

    // TurboFan最適化を強制
    b.eval("%PrepareFunctionForOptimization(%@)", with: [f])
    for _ in 0..<3 {
        b.callFunction(f, withArgs: [b.loadInt(42)])
    }
    b.eval("%OptimizeFunctionOnNextCall(%@)", with: [f])
    b.callFunction(f, withArgs: [b.loadInt(42)])
}

// WasmFuzzerテンプレートを追加
fileprivate let WasmFuzzer = ProgramTemplate("WasmFuzzer") { b in
    b.buildTryCatchFinally(tryBody: {
        let WebAssembly = b.loadBuiltin("WebAssembly")
        
        // 基本的なWASMモジュールを作成
        let wasmBytes = b.createArray(with: [
            // マジックナンバーとバージョン
            b.loadInt(0x00), b.loadInt(0x61), b.loadInt(0x73), b.loadInt(0x6d),
            b.loadInt(0x01), b.loadInt(0x00), b.loadInt(0x00), b.loadInt(0x00),
            // タイプセクション
            b.loadInt(0x01), b.loadInt(0x07), b.loadInt(0x01),
            b.loadInt(0x60), b.loadInt(0x02), b.loadInt(0x7f), b.loadInt(0x7f),
            b.loadInt(0x01), b.loadInt(0x7f)
        ])
        
        let uint8Array = b.construct(b.loadBuiltin("Uint8Array"), withArgs: [wasmBytes])
        let module = b.construct(b.getProperty("Module", of: WebAssembly), withArgs: [uint8Array])
        let instance = b.construct(b.getProperty("Instance", of: WebAssembly), withArgs: [module])
        
        // エクスポートされた関数を呼び出し
        let exports = b.getProperty("exports", of: instance)
        b.callFunction(b.getProperty("add", of: exports), withArgs: [b.loadInt(42), b.loadInt(13)])
        
    }, catchBody: { error in
        b.loadUndefined()
    })
}

// ComplexWasmFuzzerテンプレートを追加
fileprivate let ComplexWasmFuzzer = ProgramTemplate("ComplexWasmFuzzer") { b in
    b.buildTryCatchFinally(tryBody: {
        let WebAssembly = b.loadBuiltin("WebAssembly")
        
        // メモリとテーブルを作成
        let memory = b.construct(b.getProperty("Memory", of: WebAssembly), withArgs: [
            b.createObject(with: ["initial": b.loadInt(1), "maximum": b.loadInt(10)])
        ])
        
        let table = b.construct(b.getProperty("Table", of: WebAssembly), withArgs: [
            b.createObject(with: [
                "element": b.loadString("anyfunc"),
                "initial": b.loadInt(1),
                "maximum": b.loadInt(10)
            ])
        ])
        
        // インポートオブジェクトを作成
        let importObj = b.createObject(with: [
            "env": b.createObject(with: [
                "memory": memory,
                "table": table,
                "log": b.buildPlainFunction(with: .parameters(n: 1)) { args in
                    b.doReturn(args[0])
                }
            ])
        ])
        
        // より複雑なWASMモジュールを作成
        let wasmBytes = b.createArray(with: [
            // マジックナンバーとバージョン
            b.loadInt(0x00), b.loadInt(0x61), b.loadInt(0x73), b.loadInt(0x6d),
            b.loadInt(0x01), b.loadInt(0x00), b.loadInt(0x00), b.loadInt(0x00),
            // より複雑なセクションを含む...
            b.loadInt(0x02), b.loadInt(0x07), b.loadInt(0x01),
            b.loadInt(0x03), b.loadInt(0x65), b.loadInt(0x6e), b.loadInt(0x76)
        ])
        
        let uint8Array = b.construct(b.loadBuiltin("Uint8Array"), withArgs: [wasmBytes])
        
        // モジュールの検証と作成
        b.callMethod("validate", on: WebAssembly, withArgs: [uint8Array])
        let module = b.construct(b.getProperty("Module", of: WebAssembly), withArgs: [uint8Array])
        
        // インスタンス化とメモリ操作
        let instance = b.construct(b.getProperty("Instance", of: WebAssembly), 
                                 withArgs: [module, importObj])
        
        // メモリ操作のテスト
        let memoryView = b.construct(b.loadBuiltin("Int32Array"), 
                                   withArgs: [b.getProperty("buffer", of: memory)])
        
        // ランダムなメモリアクセス
        for _ in 0..<5 {
            let index = b.loadInt(Int64.random(in: 0..<256))
            b.callMethod("set", on: memoryView, withArgs: [index, b.loadInt(42)])
        }
        
    }, catchBody: { error in
        b.loadUndefined()
    })
}

// メモリ操作のジェネレータ
fileprivate let WasmMemoryOperationsGenerator = CodeGenerator("WasmMemoryOperationsGenerator") { b in
    b.buildTryCatchFinally(tryBody: {
        let wasmMemory = b.loadBuiltin("WebAssembly.Memory")
        let memoryDesc = b.createObject(with: [
            "initial": b.loadInt(1),
            "maximum": b.loadInt(10),
            "shared": b.loadBool(probability(0.2))
        ])
        let memory = b.construct(wasmMemory, withArgs: [memoryDesc])
        
        // 様々な型付き配列でのアクセス
        let viewTypes = ["Int8Array", "Int16Array", "Int32Array", "Float32Array", "Float64Array", 
                        "Uint8Array", "Uint16Array", "Uint32Array"]
        
        for viewType in viewTypes {
            if probability(0.3) {
                let view = b.construct(b.loadBuiltin(viewType), 
                                     withArgs: [b.getProperty("buffer", of: memory)])
                
                // ランダムな位置に書き込み
                let index = b.loadInt(Int64.random(in: 0..<256))
                let value = b.loadInt(Int64.random(in: -128..<128))
                b.callMethod("set", on: view, withArgs: [index, value])
                
                // 読み取りテスト
                b.callMethod("get", on: view, withArgs: [index])
                
                // 範囲外アクセスのテスト
                if probability(0.1) {
                    let outOfBoundsIndex = b.loadInt(Int64.random(in: 1000..<2000))
                    b.callMethod("get", on: view, withArgs: [outOfBoundsIndex])
                }
            }
        }
        
        // メモリの成長テスト
        if probability(0.2) {
            b.callMethod("grow", on: memory, withArgs: [b.loadInt(1)])
        }
    }, catchBody: { error in
        b.loadUndefined()
    })
}

// メモリ境界テストのジェネレータ
fileprivate let WasmMemoryBoundaryTest = CodeGenerator("WasmMemoryBoundaryTest") { b in
    b.buildTryCatchFinally(tryBody: {
        let memory = b.construct(b.loadBuiltin("WebAssembly.Memory"), 
                               withArgs: [b.createObject(with: [
                                   "initial": b.loadInt(1),
                                   "maximum": b.loadInt(2)
                               ])])
        
        // 境界値でのアクセス
        let view = b.construct(b.loadBuiltin("Int32Array"), 
                             withArgs: [b.getProperty("buffer", of: memory)])
        
        // ページサイズ境界でのアクセス
        let pageSize = 65536
        let indices = [
            pageSize - 4,    // ページ境界直前
            pageSize,        // ページ境界
            pageSize + 4     // ページ境界直後
        ]
        
        for index in indices {
            b.callMethod("get", on: view, withArgs: [b.loadInt(Int64(index))])
        }
        
        // メモリ成長時の境界テスト
        b.callMethod("grow", on: memory, withArgs: [b.loadInt(1)])
        b.callMethod("get", on: view, withArgs: [b.loadInt(Int64(pageSize * 2 - 4))])
    }, catchBody: { error in
        b.loadUndefined()
    })
}

// 並行アクセステストのジェネレータ
fileprivate let WasmConcurrentAccessTest = CodeGenerator("WasmConcurrentAccessTest") { b in
    b.buildTryCatchFinally(tryBody: {
        let memory = b.construct(b.loadBuiltin("WebAssembly.Memory"), 
                               withArgs: [b.createObject(with: [
                                   "initial": b.loadInt(1),
                                   "maximum": b.loadInt(2),
                                   "shared": b.loadBool(true)
                               ])])
        
        // 共有メモリへの並行アクセス
        let view = b.construct(b.loadBuiltin("Int32Array"), 
                             withArgs: [b.getProperty("buffer", of: memory)])
        
        // Atomics APIを使用
        let atomics = b.loadBuiltin("Atomics")
        let index = b.loadInt(0)
        let value = b.loadInt(42)
        
        b.callMethod("store", on: atomics, withArgs: [view, index, value])
        b.callMethod("load", on: atomics, withArgs: [view, index])
        b.callMethod("add", on: atomics, withArgs: [view, index, b.loadInt(1)])
        b.callMethod("sub", on: atomics, withArgs: [view, index, b.loadInt(1)])
    }, catchBody: { error in
        b.loadUndefined()
    })
}

// 型変換テストのジェネレータ
fileprivate let WasmTypeConversionTest = CodeGenerator("WasmTypeConversionTest") { b in
    b.buildTryCatchFinally(tryBody: {
        let wasmModule = b.loadBuiltin("WebAssembly")
        
        // 様々な型の変換をテストするモジュール
        let moduleBytes = b.createArray(with: [
            // マジックナンバーとバージョン
            b.loadInt(0x00), b.loadInt(0x61), b.loadInt(0x73), b.loadInt(0x6d),
            b.loadInt(0x01), b.loadInt(0x00), b.loadInt(0x00), b.loadInt(0x00),
            // タイプセクション - 様々な型のパラメータと戻り値
            b.loadInt(0x01), b.loadInt(0x07), b.loadInt(0x01),
            b.loadInt(0x60), b.loadInt(0x04),
            b.loadInt(0x7f),  // i32
            b.loadInt(0x7e),  // i64
            b.loadInt(0x7d),  // f32
            b.loadInt(0x7c),  // f64
            b.loadInt(0x01), b.loadInt(0x7f)  // 戻り値 i32
        ])
        
        let module = b.construct(b.getProperty("Module", of: wasmModule), withArgs: [moduleBytes])
        let instance = b.construct(b.getProperty("Instance", of: wasmModule), withArgs: [module])
        
        // エッジケースの値でテスト
        let exports = b.getProperty("exports", of: instance)
        let testFunc = b.getProperty("test", of: exports)
        
        // 様々な型の値でテスト
        let testValues = [
            b.loadInt(0x7fffffff),     // i32 最大値
            b.loadInt(-0x80000000),    // i32 最小値
            b.loadFloat(3.14159),      // f32
            b.loadFloat(1.0e38),       // f32 大きな値
            b.loadFloat(1.0e-38)       // f32 小さな値
        ]
        
        for value in testValues {
            b.callFunction(testFunc, withArgs: [value])
        }
    }, catchBody: { error in
        b.loadUndefined()
    })
}

// 基本的なWASM操作のジェネレータ
fileprivate let WasmGenerator = CodeGenerator("WasmGenerator") { b in
    b.buildTryCatchFinally(tryBody: {
        let wasmModule = b.loadBuiltin("WebAssembly")
        
        // 基本的な数値演算を行うWASMモジュール
        let moduleBytes = b.createArray(with: [
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
            b.loadInt(0x03), b.loadInt(3),  // "add"の長さ(3)を直接指定
            b.loadString("add"),
            b.loadInt(0x00), b.loadInt(0x00)
        ])
        
        let module = b.construct(b.getProperty("Module", of: wasmModule), withArgs: [moduleBytes])
        let instance = b.construct(b.getProperty("Instance", of: wasmModule), withArgs: [module])
        
        // エクスポートされた関数を呼び出し
        let exports = b.getProperty("exports", of: instance)
        b.callFunction(b.getProperty("add", of: exports), withArgs: [b.loadInt(42), b.loadInt(13)])
    }, catchBody: { error in
        b.loadUndefined()
    })
}

// 基本的なコードジェネレータを修正
fileprivate let BasicCodeGenerator = CodeGenerator("BasicCodeGenerator") { b in
    withEqualProbability({
        // 数値演算
        let x = b.loadInt(Int64.random(in: -100...100))
        let y = b.loadInt(Int64.random(in: -100...100))
        b.binary(x, y, with: chooseUniform(from: [.Add, .Sub, .Mul, .Div]))
    }, {
        // 関数呼び出し
        let f = b.buildPlainFunction(with: .parameters(n: Int.random(in: 0...3))) { args in
            if !args.isEmpty {
                b.doReturn(args[0])
            }
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    }, {
        // オブジェクト操作
        let obj = b.createObject(with: ["x": b.loadInt(42)])
        b.setProperty("y", of: obj, to: b.loadString("test"))
        b.getProperty("x", of: obj)
    })
}

let v8Profile: Profile = Profile(
    processArgs: { randomize in
        var args = [
            "--expose-gc",
            "--expose-externalize-string",
            "--omit-quit",
            "--allow-natives-syntax",
            "--fuzzing",
            "--jit-fuzzing",
            "--future",
            "--harmony",
            "--js-staging",
            "--wasm-staging",
            "--wasm-simd",
            "--experimental-wasm-gc",
            "--experimental-wasm-stringref",
            "--experimental-wasm-type-reflection"
        ]

        guard randomize else { return args }

        // 最適化関連のフラグを追加
        if probability(0.1) {
            args.append("--turboshaft-typed-optimizations")
        }

        if probability(0.1) {
            args.append("--maglev-inlining")
        }

        if probability(0.1) {
            args.append("--concurrent-sparkplug")
        }

        // メモリ関連のフラグを追加
        if probability(0.1) {
            args.append("--stress-concurrent-allocation")
        }

        if probability(0.1) {
            args.append("--stress-incremental-marking")
        }

        // 検証フラグを追加
        if probability(0.1) {
            args.append("--verify-heap-skip-remembered-set")
        }

        return args
    },

    // We typically fuzz without any sanitizer instrumentation, but if any sanitizers are active, "abort_on_error=1" must probably be set so that sanitizer errors can be detected.
    processEnv: [:],

    maxExecsBeforeRespawn: 1000,

    timeout: 250,

    codePrefix: """
                """,

    codeSuffix: """
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // Check that the fuzzilli integration is available.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),

        // Check that common crash types are detected.
        // IMMEDIATE_CRASH()
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
        // CHECK failure
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldCrash),
        // DCHECK failure
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldCrash),
        // Wild-write
        ("fuzzilli('FUZZILLI_CRASH', 3)", .shouldCrash),
        // Check that DEBUG is defined.
        ("fuzzilli('FUZZILLI_CRASH', 8)", .shouldCrash),

        // TODO we could try to check that OOM crashes are ignored here ( with.shouldNotCrash).
    ],

    additionalCodeGenerators: [
        (ForceJITCompilationThroughLoopGenerator,  5),
        (ForceTurboFanCompilationGenerator,        5),
        (ForceMaglevCompilationGenerator,          5),
        (TurbofanVerifyTypeGenerator,             10),
        (WorkerGenerator,                         10),
        (GcGenerator,                             10),
        
        // 基本的なコードジェネレータを追加
        (BasicCodeGenerator,                      50),
        
        // WebAssembly関連のジェネレータ
        (WasmGenerator,                           50),
        (WasmMemoryOperationsGenerator,           40),
        (WasmStructGenerator,                     40),
        (WasmTableGenerator,                      40),
        (WasmArrayGenerator,                      40),
        (WasmGlobalGenerator,                     40),
        
        // エッジケーステスト
        (WasmMemoryBoundaryTest,                 30),
        (WasmConcurrentAccessTest,               25),
        (WasmTypeConversionTest,                 35),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MapTransitionFuzzer,    1),
        (ValueSerializerFuzzer,  1),
        (RegExpFuzzer,           1),
        (WasmFuzzer,             2),
        (ComplexWasmFuzzer,      2),
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"            : .function([] => (.undefined | .jsPromise)),
        "d8"            : .object(),
        "Worker"        : .constructor([.anything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
        
        // WebAssembly関連のビルトイン
        "WebAssembly"   : .object(withMethods: ["compile", "validate", "instantiate"]),
        "WebAssembly.Module"    : .constructor([.object(ofGroup: "TypedArray")] => .object()),
        "WebAssembly.Instance"  : .constructor([.object()] => .object()),
        "WebAssembly.Memory"    : .constructor([.object()] => .object()),
        "WebAssembly.Table"     : .constructor([.object()] => .object()),
        
        // Atomicsの型定義
        "Atomics"       : .object(withMethods: [
            "add",
            "and",
            "compareExchange",
            "exchange",
            "load",
            "or",
            "store",
            "sub",
            "xor",
            "wait",
            "notify",
            "isLockFree"
        ]),
        
        // SharedArrayBuffer型の定義
        "SharedArrayBuffer": .constructor([.integer] => .object()),

        // TypedArray関連のビルトイン（重複を削除）
        "Int8Array"     : .constructor([.integer] => .object(ofGroup: "TypedArray")),
        "Uint8Array"    : .constructor([.integer] => .object(ofGroup: "TypedArray")),
        "Int16Array"    : .constructor([.integer] => .object(ofGroup: "TypedArray")),
        "Uint16Array"   : .constructor([.integer] => .object(ofGroup: "TypedArray")),
        "Int32Array"    : .constructor([.integer] => .object(ofGroup: "TypedArray")),
        "Uint32Array"   : .constructor([.integer] => .object(ofGroup: "TypedArray")),
        "Float32Array"  : .constructor([.integer] => .object(ofGroup: "TypedArray")),
        "Float64Array"  : .constructor([.integer] => .object(ofGroup: "TypedArray"))
    ],

    // TypedArrayグループを修正
    additionalObjectGroups: [
        ObjectGroup(
            name: "TypedArray",
            instanceType: .object(),
            properties: [:],
            methods: [
                "set": [.object(), .integer] => .undefined,
                "subarray": [.integer, .integer] => .object(),
                "slice": [.integer, .integer] => .object(),
                "fill": [.integer, .integer, .integer] => .object(),
                "copyWithin": [.integer, .integer, .integer] => .object()
            ]
        )
    ],

    optionalPostProcessor: nil
)
