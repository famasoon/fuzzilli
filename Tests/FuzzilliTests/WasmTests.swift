// Copyright 2023 Google LLC
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

import XCTest
@testable import Fuzzilli

func testForOutput(program: String, runner: JavaScriptExecutor, outputString: String) {
        let result: JavaScriptExecutor.Result
        do {
            result = try runner.executeScript(program)
        } catch {
            fatalError("Could not execute Script")
        }

        XCTAssertEqual(result.output, outputString)
}

class WasmFoundationTests: XCTestCase {
    func testFunction() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: Signature(expects: [], returns: ILType.wasmi32)) { function, _ in
                let constVar = function.consti32(1338)
                function.wasmReturn(constVar)
            }

            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([.wasmi64]), returns: .wasmi64)) { function, arg in
                let var64 = function.consti64(41)
                let added = function.wasmi64BinOp(var64, arg[0], binOpKind: WasmIntegerBinaryOpKind.Add)
                function.wasmReturn(added)
            }

            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([.wasmi64, .wasmi64]), returns: .wasmi64)) { function, arg in
                let subbed = function.wasmi64BinOp(arg[0], arg[1], binOpKind: WasmIntegerBinaryOpKind.Sub)
                function.wasmReturn(subbed)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())

        let num = b.loadBigInt(1)
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: module.getModuleVariable(), withArgs: [num])

        let res2 = b.callMethod(module.getExportedMethod(at: 2), on: module.getModuleVariable(), withArgs: [res1, num])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res2)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n42\n41\n")
    }

    func testExportNaming() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        // This test tests whether re-exported imports and module defined globals are re-ordered from the typer.
        let wasmGlobali32: Variable = b.createWasmGlobal(wasmGlobal: .wasmi32(1337), isMutable: true)
        assert(b.type(of: wasmGlobali32) == .object(ofGroup: "WasmGlobal.i32"))

        let wasmGlobalf32: Variable = b.createWasmGlobal(wasmGlobal: .wasmf32(42.0), isMutable: true)

        let module = b.buildWasmModule { wasmModule in
            // Imports are always before internal globals, this breaks the logic if we add a global and then import a global.
            wasmModule.addGlobal(importing: wasmGlobalf32)
            wasmModule.addGlobal(wasmGlobal: .wasmi64(4141), isMutable: true)
            wasmModule.addGlobal(importing: wasmGlobali32)

        }

        let nameOfExportedGlobals = [WasmLifter.nameOfGlobal(0), WasmLifter.nameOfGlobal(1), WasmLifter.nameOfGlobal(2)]

        assert(b.type(of: module.getModuleVariable()) == .object(withProperties: nameOfExportedGlobals))

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        // Now let's actually see what the re-exported values are and see that the types don't match with what the programbuilder will see.
        // TODO: Is this an issue? will the programbuilder still be queriable for variables? I think so, it is internally consistent within the module....
        let firstExport = b.getProperty(nameOfExportedGlobals[0], of: module.getModuleVariable())
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: firstExport))])

        let secondExport = b.getProperty(nameOfExportedGlobals[1], of: module.getModuleVariable())
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: secondExport))])

        let thirdExport = b.getProperty(nameOfExportedGlobals[2], of: module.getModuleVariable())
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: thirdExport))])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "42\n4141\n1337\n")
    }

    func testImports() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let functionA = b.buildPlainFunction(with: .parameters(.bigint)) { args in
            let varA = b.loadBigInt(1)
            let added = b.binary(varA, args[0], with: .Add)
            b.doReturn(added)
        }

        assert(b.type(of: functionA).signature == [.bigint] => .bigint)

        let functionB = b.buildArrowFunction(with: .parameters(.integer)) { args in
            let varB = b.loadInt(2)
            let subbed = b.binary(varB, args[0], with: .Sub)
            b.doReturn(subbed)
        }
        // We are unable to determine that .integer - .integer == .integer here as INT_MAX + 1 => float
        assert(b.type(of: functionB).signature == [.integer] => .number)

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, args in
                let varA = function.wasmJsCall(function: functionA, withArgs: [args[0]])
                function.wasmReturn(varA)
            }

            wasmModule.addWasmFunction(with: [] => .wasmf32) { function, _ in
                let varA = function.consti32(1337)
                let varRet = function.wasmJsCall(function: functionB, withArgs: [varA])
                function.wasmReturn(varRet)
            }
        }

        let val = b.loadBigInt(2)
        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable(), withArgs: [val])
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: module.getModuleVariable())

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "3\n-1335\n")
    }

    func testBasics() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([]), returns: .wasmi32)) { function, _ in
                let varA = function.consti32(42)
                function.wasmReturn(varA)
            }

            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([.wasmi64]), returns: .wasmi64)) { function, arg in
                let varA = function.consti64(41)
                let added = function.wasmi64BinOp(varA, arg[0], binOpKind: .Add)
                function.wasmReturn(added)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())
        let integer = b.loadBigInt(1)
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: module.getModuleVariable(), withArgs: [integer])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "42\n42\n")
    }

    func testReassigns() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, params in
                let varA = function.consti64(1338)
                // reassign params[0] = varA
                function.wasmReassign(variable: params[0], to: varA)
                function.wasmReturn(params[0])
            }

            let globA = wasmModule.addGlobal(wasmGlobal: .wasmi64(1337), isMutable: true)
            let globB = wasmModule.addGlobal(wasmGlobal: .wasmi64(1338), isMutable: true)

            wasmModule.addWasmFunction(with: [] => .nothing) { function, _ in
                function.wasmReassign(variable:  globA, to: globB)
            }

            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, params in
                // reassign params[0] = params[0]
                function.wasmReassign(variable: params[0], to: params[0])
                function.wasmReturn(params[0])
            }

        }

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let _ = b.callMethod("w1", on: module.getModuleVariable(), withArgs: [b.loadBigInt(10)])

        let out = b.callMethod("w0", on: module.getModuleVariable(), withArgs: [b.loadBigInt(10)])
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out)])

        let _ = b.callMethod("w2", on: module.getModuleVariable(), withArgs: [b.loadBigInt(20)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n")
    }

    func testGlobals() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let wasmGlobali64: Variable = b.createWasmGlobal(wasmGlobal: .wasmi64(1337), isMutable: true)
        assert(b.type(of: wasmGlobali64) == .object(ofGroup: "WasmGlobal.i64"))

        let module = b.buildWasmModule { wasmModule in
            let global = wasmModule.addGlobal(wasmGlobal: .wasmi64(1339), isMutable: true)
            let importedGlobal = wasmModule.addGlobal(importing: wasmGlobali64)

            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let varA = function.consti64(1338)
                let varB = function.consti64(4242)
                function.wasmStoreGlobal(globalVariable: global, to: varB)
                let global = function.wasmLoadGlobal(globalVariable: global)
                function.wasmStoreGlobal(globalVariable: importedGlobal, to: varA)
                function.wasmReturn(global)
            }
        }

        let _ = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())

        let nameOfExportedGlobals = [WasmLifter.nameOfGlobal(0), WasmLifter.nameOfGlobal(1)]
        let nameOfExportedFunctions = [WasmLifter.nameOfFunction(0)]

        assert(b.type(of: module.getModuleVariable()) == .object(withProperties: nameOfExportedGlobals, withMethods: nameOfExportedFunctions))


        let value = b.getProperty("value", of: wasmGlobali64)
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: value)])

        let wg0 = b.getProperty(nameOfExportedGlobals[0], of: module.getModuleVariable())
        let valueWg0 = b.getProperty("value", of: wg0)
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: valueWg0)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n4242\n")
    }

    func testTables() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let javaScriptTable = b.createWasmTable(tableType: .externRefTable, minSize: 10, maxSize: 20)

        let object = b.createObject(with: ["a": b.loadInt(41), "b": b.loadInt(42)])

        // Set a value into the table
        b.callMethod("set", on: javaScriptTable, withArgs: [b.loadInt(1), object])

        let module = b.buildWasmModule { wasmModule in
            // Imports are always before internal tables, this breaks the logic if we add a table and then import a table.
            // TODO: Track imports and tables?
            let tableRef = wasmModule.addTable(tableType: .wasmFuncRef, minSize: 2)
            let javaScriptTableRef = wasmModule.addTable(importing: javaScriptTable)

            wasmModule.addWasmFunction(with: [] => .wasmExternRef) { function, _ in
                let offset = function.consti32(0)
                var ref = function.wasmTableGet(tableRef: tableRef, idx: offset)
                let offset1 = function.consti32(1)
                function.wasmTableSet(tableRef: tableRef, idx: offset1, to: ref)
                ref = function.wasmTableGet(tableRef: tableRef, idx: offset1)
                let otherRef = function.wasmTableGet(tableRef: javaScriptTableRef, idx: offset1)
                function.wasmReturn(otherRef)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let json = b.createNamedVariable(forBuiltin: "JSON")
        b.callFunction(outputFunc, withArgs: [b.callMethod("stringify", on: json, withArgs: [res0])])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "{\"a\":41,\"b\":42}\n")
    }

    func testMemories() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let ten = b.loadInt(10)
        let twenty = b.loadInt(20)

        let config = b.createObject(with: ["initial": ten, "maximum": twenty])
        let wasm = b.createNamedVariable(forBuiltin: "WebAssembly")
        let wasmMemoryConstructor = b.getProperty("Memory", of: wasm)
        let javaScriptVar = b.construct(wasmMemoryConstructor, withArgs: [config])


        let module = b.buildWasmModule { wasmModule in
            let memoryRef = wasmModule.addMemory(importing: javaScriptVar)

            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let value = function.consti32(1337)
                let base = function.consti32(0)
                function.wasmMemorySet(memoryRef: memoryRef, base: base, offset:10, value: value)
                let val = function.wasmMemoryGet(memoryRef: memoryRef, type: .wasmi64, base: base, offset: 10)
                function.wasmReturn(val)
            }
        }

        let viewBuiltin = b.createNamedVariable(forBuiltin: "DataView")
        let view = b.construct(viewBuiltin, withArgs: [b.getProperty("buffer", of: javaScriptVar)])

        // Read the value of the memory.
        let value = b.callMethod("getUint32", on: view, withArgs: [b.loadInt(10), b.loadBool(true)])

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())

        let valueAfter = b.callMethod("getUint32", on: view, withArgs: [b.loadInt(10), b.loadBool(true)])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: value)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: valueAfter)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1337\n0\n1337\n")
    }

    func testLoops() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                // Test if we can break from this block
                // We should expect to have executed the first wasmReassign which sets marker to 11
                let marker = function.consti64(10)
                function.wasmBuildBlock(with: Signature(withParameterCount: 0)) { label, args in
                    let a = function.consti64(11)
                    function.wasmReassign(variable: marker, to: a)
                    function.wasmBuildBlock(with: Signature(withParameterCount: 0)) { _, _ in
                        // TODO: write codegenerators that use this somehow.
                        // Break to the outer block, this verifies that we can break out of nested block
                        function.wasmBranch(to: label)
                    }
                    let b = function.consti64(12)
                    function.wasmReassign(variable: marker, to: b)
                }

                // Do a simple loop that adds 2 to this variable 10 times.
                let variable = function.consti64(1337)
                let ctr = function.consti32(0)
                let max = function.consti32(10)
                let one = function.consti32(1)

                function.wasmBuildLoop(with: Signature(withParameterCount: 0)) { label, args in
                    let result = function.wasmi32BinOp(ctr, one, binOpKind: .Add)
                    let varUpdate = function.wasmi64BinOp(variable, function.consti64(2), binOpKind: .Add)
                    function.wasmReassign(variable: ctr, to: result)
                    function.wasmReassign(variable: variable, to: varUpdate)
                    let comp = function.wasmi32CompareOp(ctr, max, using: .Lt_s)
                    function.wasmBranchIf(comp, to: label)
                }

                // Now combine the result of the break and the loop into one and return it.
                // This should return 1337 + 20 == 1357, 1357 + 11 = 1368
                let result = function.wasmi64BinOp(variable, marker, binOpKind: .Add)

                function.wasmReturn(result)
            }
        }

        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1368\n")
    }

    func testIfs() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let variable = args[0]
                let condVariable = function.consti32(10);
                let result = function.consti32(0);

                let comp = function.wasmi32CompareOp(variable, condVariable, using: .Lt_s)

                function.wasmBuildIfElse(comp, ifBody: {
                    let tmp = function.wasmi32BinOp(variable, condVariable, binOpKind: .Add)
                    function.wasmReassign(variable: result, to: tmp)
                }, elseBody: {
                    let tmp = function.wasmi32BinOp(variable, condVariable, binOpKind: .Sub)
                    function.wasmReassign(variable: result, to: tmp)
                })

                function.wasmReturn(result)
            }
        }

        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable(), withArgs: [b.loadInt(1337)])
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1327\n")
    }
}

class WasmNumericalTests: XCTestCase {
    // Integer BinaryOperations
    func testi64BinaryOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per binary operator.
        let module = b.buildWasmModule { wasmModule in
            for binOp in WasmIntegerBinaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi64, .wasmi64] => .wasmi64) { function, args in
                    let result = function.wasmi64BinOp(args[0], args[1], binOpKind: binOp)
                    function.wasmReturn(result)
                }
            }
        }

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        let addFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Add.rawValue))
        let subFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Sub.rawValue))
        let mulFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Mul.rawValue))
        let divSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Div_s.rawValue))
        let divUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Div_u.rawValue))
        let remSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rem_s.rawValue))
        let remUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rem_u.rawValue))
        let andFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.And.rawValue))
        let orFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Or.rawValue))
        let xorFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Xor.rawValue))
        let shlFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shl.rawValue))
        let shrSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shr_s.rawValue))
        let shrUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shr_u.rawValue))
        let rotlFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rotl.rawValue))
        let rotrFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rotr.rawValue))

        // 1n + 1n = 2n
        ExpectEq(addFunc, [b.loadBigInt(1), b.loadBigInt(1)], "2")

        // 1n - 1n = 0n
        ExpectEq(subFunc, [b.loadBigInt(1), b.loadBigInt(1)], "0")

        // 2n * 4n = 8n
        ExpectEq(mulFunc, [b.loadBigInt(2), b.loadBigInt(4)], "8")

        // -8n / -4n = 2n
        ExpectEq(divSFunc, [b.loadBigInt(-8), b.loadBigInt(-4)], "2")

        // This -16 will be represented by a big unsigned number and then dividing it by 4 should be 4611686018427387900n
        // -16n / 4n = 4611686018427387900n
        ExpectEq(divUFunc, [b.loadBigInt(-16), b.loadBigInt(4)], "4611686018427387900")

        // -17n % 4n = -1n
        ExpectEq(remSFunc, [b.loadBigInt(-17), b.loadBigInt(4)], "-1")

        // -17n (which is 18446744073709551599n) % 4n = 3n
        ExpectEq(remUFunc, [b.loadBigInt(-17), b.loadBigInt(4)], "3")

        // 1n & 3n = 1n
        ExpectEq(andFunc, [b.loadBigInt(1), b.loadBigInt(3)], "1")

        // 1n | 4n = 5n
        ExpectEq(orFunc, [b.loadBigInt(1), b.loadBigInt(4)], "5")

        // 3n ^ 5n = 6n
        ExpectEq(xorFunc, [b.loadBigInt(3), b.loadBigInt(5)], "6")

        // 3n << 5n = 96n
        ExpectEq(shlFunc, [b.loadBigInt(3), b.loadBigInt(5)], "96")

        // -3n >> 1n = -2n
        ExpectEq(shrSFunc, [b.loadBigInt(-3), b.loadBigInt(1)], "-2")

        // -3n (18446744073709551613n) >> 1n = 9223372036854775806n
        ExpectEq(shrUFunc, [b.loadBigInt(-3), b.loadBigInt(1)], "9223372036854775806")

        // -3n rotl 1n = -5n
        ExpectEq(rotlFunc, [b.loadBigInt(-3), b.loadBigInt(1)], "-5")

        // 1n rotr 1n = -9223372036854775808n
        ExpectEq(rotrFunc, [b.loadBigInt(1), b.loadBigInt(1)], "-9223372036854775808")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testi32BinaryOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per binary operator.
        let module = b.buildWasmModule { wasmModule in
            for binOp in WasmIntegerBinaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => .wasmi32) { function, args in
                    let result = function.wasmi32BinOp(args[0], args[1], binOpKind: binOp)
                    function.wasmReturn(result)
                }
            }
        }

        let addFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Add.rawValue))
        let subFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Sub.rawValue))
        let mulFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Mul.rawValue))
        let divSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Div_s.rawValue))
        let divUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Div_u.rawValue))
        let remSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rem_s.rawValue))
        let remUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rem_u.rawValue))
        let andFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.And.rawValue))
        let orFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Or.rawValue))
        let xorFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Xor.rawValue))
        let shlFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shl.rawValue))
        let shrSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shr_s.rawValue))
        let shrUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shr_u.rawValue))
        let rotlFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rotl.rawValue))
        let rotrFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rotr.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1 + 1 = 2
        ExpectEq(addFunc, [b.loadInt(1), b.loadInt(1)], "2")

        // 1 - 1 = 0
        ExpectEq(subFunc, [b.loadInt(1), b.loadInt(1)], "0")

        // 2 * 4 = 8
        ExpectEq(mulFunc, [b.loadInt(2), b.loadInt(4)], "8")

        // -8 / -4 = 2
        ExpectEq(divSFunc, [b.loadInt(-8), b.loadInt(-4)], "2")

        // -16 / 4 = 1073741820
        ExpectEq(divUFunc, [b.loadInt(-16), b.loadInt(4)], "1073741820")

        // -17 % 4 = -1
        ExpectEq(remSFunc, [b.loadInt(-17), b.loadInt(4)], "-1")

        // -17 % 4 = 3
        ExpectEq(remUFunc, [b.loadInt(-17), b.loadInt(4)], "3")

        // 1 & 3 = 1
        ExpectEq(andFunc, [b.loadInt(1), b.loadInt(3)], "1")

        // 1 | 4 = 5
        ExpectEq(orFunc, [b.loadInt(1), b.loadInt(4)], "5")

        // 3 ^ 5 = 6
        ExpectEq(xorFunc, [b.loadInt(3), b.loadInt(5)], "6")

        // 3 << 5 = 96
        ExpectEq(shlFunc, [b.loadInt(3), b.loadInt(5)], "96")

        // -3 >> 1 = -2
        ExpectEq(shrSFunc, [b.loadInt(-3), b.loadInt(1)], "-2")

        // -3 >> 1 = 2147483646
        ExpectEq(shrUFunc, [b.loadInt(-3), b.loadInt(1)], "2147483646")

        // -3 rotl 1 = -5
        ExpectEq(rotlFunc, [b.loadInt(-3), b.loadInt(1)], "-5")

        // 1 rotr 1 = -2147483648
        ExpectEq(rotrFunc, [b.loadInt(1), b.loadInt(1)], "-2147483648")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Float Binary Operations
    func testf64BinaryOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per binary operator.
        let module = b.buildWasmModule { wasmModule in
            for binOp in WasmFloatBinaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf64, .wasmf64] => .wasmf64) { function, args in
                    let result = function.wasmf64BinOp(args[0], args[1], binOpKind: binOp)
                    function.wasmReturn(result)
                }
            }
        }

        let addFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Add.rawValue))
        let subFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Sub.rawValue))
        let mulFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Mul.rawValue))
        let divFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Div.rawValue))
        let minFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Min.rawValue))
        let maxFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Max.rawValue))
        let copysignFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Copysign.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1 + 1.05 = 2.05
        ExpectEq(addFunc, [b.loadFloat(1), b.loadFloat(1.05)], "2.05")

        // 1.05 - 1 = 0.050000000000000044
        ExpectEq(subFunc, [b.loadFloat(1.05), b.loadFloat(1)], "0.050000000000000044")

        // 2.5 * 4 = 10
        ExpectEq(mulFunc, [b.loadFloat(2.5), b.loadFloat(4)], "10")

        // -11 / -2.5 = 4.4
        ExpectEq(divFunc, [b.loadFloat(-11), b.loadFloat(-2.5)], "4.4")

        // Min(-3.1, 4.25) = -3.1
        ExpectEq(minFunc, [b.loadFloat(-3.1), b.loadFloat(4.25)], "-3.1")

        // Max(5.3, 5.31) = 5.31
        ExpectEq(maxFunc, [b.loadFloat(5.3), b.loadFloat(5.31)], "5.31")

        // Copies the sign of the second number, onto the first number.
        // CopySign(-3.1, 4.2) = 3.1
        ExpectEq(copysignFunc, [b.loadFloat(-3.1), b.loadFloat(4.2)], "3.1")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testf32BinaryOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per binary operator.
        let module = b.buildWasmModule { wasmModule in
            for binOp in WasmFloatBinaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf32, .wasmf32] => .wasmf32) { function, args in
                    let result = function.wasmf32BinOp(args[0], args[1], binOpKind: binOp)
                    function.wasmReturn(result)
                }
            }
        }

        let addFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Add.rawValue))
        let subFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Sub.rawValue))
        let mulFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Mul.rawValue))
        let divFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Div.rawValue))
        let minFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Min.rawValue))
        let maxFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Max.rawValue))
        let copysignFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Copysign.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1 + 1.05 = 2.049999952316284
        ExpectEq(addFunc, [b.loadFloat(1), b.loadFloat(1.05)], "2.049999952316284")

        // 1.05 - 1 = 0.04999995231628418
        ExpectEq(subFunc, [b.loadFloat(1.05), b.loadFloat(1)], "0.04999995231628418")

        // 2.5 * 4 = 10
        ExpectEq(mulFunc, [b.loadFloat(2.5), b.loadFloat(4)], "10")

        // -11 / -2.5 = 4.400000095367432
        ExpectEq(divFunc, [b.loadFloat(-11), b.loadFloat(-2.5)], "4.400000095367432")

        // Min(-3.1, 4.25) = -3.0999999046325684
        ExpectEq(minFunc, [b.loadFloat(-3.1), b.loadFloat(4.25)], "-3.0999999046325684")

        // Max(5.3, 5.31) = 5.309999942779541
        ExpectEq(maxFunc, [b.loadFloat(5.3), b.loadFloat(5.31)], "5.309999942779541")

        // Copies the sign of the second number, onto the first number.
        // CopySign(-3.1, 4.2) = 3.0999999046325684
        ExpectEq(copysignFunc, [b.loadFloat(-3.1), b.loadFloat(4.2)], "3.0999999046325684")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Integer Unary Operations
    func testi64UnaryOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per unary operator.
        let module = b.buildWasmModule { wasmModule in
            for unOp in WasmIntegerUnaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, args in
                    let result = function.wasmi64UnOp(args[0], unOpKind: unOp)
                    function.wasmReturn(result)
                }
            }
        }

        let clzFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Clz.rawValue))
        let ctzFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Ctz.rawValue))
        let popcntFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Popcnt.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // Clz(1n) = 63n
        ExpectEq(clzFunc, [b.loadBigInt(1)], "63")

        // Ctz(2n) = 1n
        ExpectEq(ctzFunc, [b.loadBigInt(2)], "1")

        // Popcnt(130n) = 2n
        ExpectEq(popcntFunc, [b.loadBigInt(130)], "2")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testi32UnaryOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per unary operator.
        let module = b.buildWasmModule { wasmModule in
            for unOp in WasmIntegerUnaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                    let result = function.wasmi32UnOp(args[0], unOpKind: unOp)
                    function.wasmReturn(result)
                }
            }
        }

        let clzFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Clz.rawValue))
        let ctzFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Ctz.rawValue))
        let popcntFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Popcnt.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // Clz(1) = 31
        ExpectEq(clzFunc, [b.loadInt(1)], "31")

        // Ctz(2) = 1
        ExpectEq(ctzFunc, [b.loadInt(2)], "1")

        // Popcnt(130) = 2
        ExpectEq(popcntFunc, [b.loadInt(130)], "2")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Float Unary Operations
    func testf64UnaryOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per unary operator.
        let module = b.buildWasmModule { wasmModule in
            for unOp in WasmFloatUnaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf64] => .wasmf64) { function, args in
                    let result = function.wasmf64UnOp(args[0], unOpKind: unOp)
                    function.wasmReturn(result)
                }
            }
        }

        let absFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Abs.rawValue))
        let negFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Neg.rawValue))
        let ceilFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Ceil.rawValue))
        let floorFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Floor.rawValue))
        let truncFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Trunc.rawValue))
        let nearestFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Nearest.rawValue))
        let sqrtFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Sqrt.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [result])
            outputString += output + "\n"
        }

        // Abs(-1.3) = 1.3
        ExpectEq(absFunc, [b.loadFloat(-1.3)], "1.3")

        // Neg(3.1) = -3.1
        ExpectEq(negFunc, [b.loadFloat(3.1)], "-3.1")

        // Ceil(3.1) = 4
        ExpectEq(ceilFunc, [b.loadFloat(3.1)], "4")

        // Floor(3.9) = 3
        ExpectEq(floorFunc, [b.loadFloat(3.9)], "3")

        // Trunc(3.6) = 3
        ExpectEq(truncFunc, [b.loadFloat(3.6)], "3")

        // Nearest(3.501) = 4
        ExpectEq(nearestFunc, [b.loadFloat(3.501)], "4")

        // Sqrt(9) = 3
        ExpectEq(sqrtFunc, [b.loadFloat(9)], "3")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testf32UnaryOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per unary operator.
        let module = b.buildWasmModule { wasmModule in
            for unOp in WasmFloatUnaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf32] => .wasmf32) { function, args in
                    let result = function.wasmf32UnOp(args[0], unOpKind: unOp)
                    function.wasmReturn(result)
                }
            }
        }

        let absFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Abs.rawValue))
        let negFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Neg.rawValue))
        let ceilFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Ceil.rawValue))
        let floorFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Floor.rawValue))
        let truncFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Trunc.rawValue))
        let nearestFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Nearest.rawValue))
        let sqrtFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Sqrt.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // Abs(-1.3) = 1.2999999523162842
        ExpectEq(absFunc, [b.loadFloat(-1.3)], "1.2999999523162842")

        // Neg(3.1) = -3.0999999046325684
        ExpectEq(negFunc, [b.loadFloat(3.1)], "-3.0999999046325684")

        // Ceil(3.1) = 4
        ExpectEq(ceilFunc, [b.loadFloat(3.1)], "4")

        // Floor(3.9) = 3
        ExpectEq(floorFunc, [b.loadFloat(3.9)], "3")

        // Trunc(3.6) = 3
        ExpectEq(truncFunc, [b.loadFloat(3.6)], "3")

        // Nearest(3.501) = 4
        ExpectEq(nearestFunc, [b.loadFloat(3.501)], "4")

        // Sqrt(9) = 3
        ExpectEq(sqrtFunc, [b.loadFloat(9)], "3")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Integer Comparison Operations
    func testi64ComparisonOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per compare operator.
        let module = b.buildWasmModule { wasmModule in
            for compOp in WasmIntegerCompareOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi64, .wasmi64] => .wasmi32) { function, args in
                    let result = function.wasmi64CompareOp(args[0], args[1], using: compOp)
                    function.wasmReturn(result)
                }
            }

            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi32) { function, args in
                let result = function.wasmi64EqualZero(args[0])
                function.wasmReturn(result)
            }
        }

        let eqFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Eq.rawValue))
        let neFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ne.rawValue))
        let ltSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Lt_s.rawValue))
        let ltUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Lt_u.rawValue))
        let gtSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Gt_s.rawValue))
        let gtUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Gt_u.rawValue))
        let leSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Le_s.rawValue))
        let leUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Le_u.rawValue))
        let geSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ge_s.rawValue))
        let geUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ge_u.rawValue))

        // This function is added separately at the end above.
        let eqzFunc = module.getExportedMethod(at: WasmIntegerCompareOpKind.allCases.count)

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1n == 2n = 0
        ExpectEq(eqFunc, [b.loadBigInt(1), b.loadBigInt(2)], "0")

        // 1n != 2n = 1
        ExpectEq(neFunc, [b.loadBigInt(1), b.loadBigInt(2)], "1")

        // -1n < 2n = 1
        ExpectEq(ltSFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "1")

        // -1n < 2n = 0
        ExpectEq(ltUFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "0")

        // 2n < 2n = 0
        ExpectEq(ltUFunc, [b.loadBigInt(2), b.loadBigInt(2)], "0")

        // -1n > 2n = 0
        ExpectEq(gtSFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "0")

        // -1n > 2n = 1
        ExpectEq(gtUFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "1")

        // -1n <= 2n = 1
        ExpectEq(leSFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "1")

        // -1n <= 2n = 0
        ExpectEq(leUFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "0")

        // -1n >= 2n = 0
        ExpectEq(geSFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "0")

        // -1n >= 2n = 1
        ExpectEq(geUFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "1")

        // -1n == 0n = 0
        ExpectEq(eqzFunc, [b.loadBigInt(-1)], "0")

        // 0n == 0n = 1
        ExpectEq(eqzFunc, [b.loadBigInt(0)], "1")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testi32ComparisonOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per compare operator.
        let module = b.buildWasmModule { wasmModule in
            for compOp in WasmIntegerCompareOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => .wasmi32) { function, args in
                    let result = function.wasmi32CompareOp(args[0], args[1], using: compOp)
                    function.wasmReturn(result)
                }
            }

            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let result = function.wasmi32EqualZero(args[0])
                function.wasmReturn(result)
            }
        }

        let eqFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Eq.rawValue))
        let neFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ne.rawValue))
        let ltSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Lt_s.rawValue))
        let ltUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Lt_u.rawValue))
        let gtSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Gt_s.rawValue))
        let gtUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Gt_u.rawValue))
        let leSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Le_s.rawValue))
        let leUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Le_u.rawValue))
        let geSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ge_s.rawValue))
        let geUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ge_u.rawValue))

        // This function is added separately at the end above.
        let eqzFunc = module.getExportedMethod(at: WasmIntegerCompareOpKind.allCases.count)

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1 == 2 = 0
        ExpectEq(eqFunc, [b.loadInt(1), b.loadInt(2)], "0")

        // 1 != 2 = 1
        ExpectEq(neFunc, [b.loadInt(1), b.loadInt(2)], "1")

        // -1 < 2 = 1
        ExpectEq(ltSFunc, [b.loadInt(-1), b.loadInt(2)], "1")

        // -1 < 2 = 0
        ExpectEq(ltUFunc, [b.loadInt(-1), b.loadInt(2)], "0")

        // 2 < 2 = 0
        ExpectEq(ltUFunc, [b.loadInt(2), b.loadInt(2)], "0")

        // -1 > 2 = 0
        ExpectEq(gtSFunc, [b.loadInt(-1), b.loadInt(2)], "0")

        // -1 > 2 = 1
        ExpectEq(gtUFunc, [b.loadInt(-1), b.loadInt(2)], "1")

        // -1 <= 2 = 1
        ExpectEq(leSFunc, [b.loadInt(-1), b.loadInt(2)], "1")

        // -1 <= 2 = 0
        ExpectEq(leUFunc, [b.loadInt(-1), b.loadInt(2)], "0")

        // -1 >= 2 = 0
        ExpectEq(geSFunc, [b.loadInt(-1), b.loadInt(2)], "0")

        // -1 >= 2 = 1
        ExpectEq(geUFunc, [b.loadInt(-1), b.loadInt(2)], "1")

        // -1 == 0 = 0
        ExpectEq(eqzFunc, [b.loadInt(-1)], "0")

        // 0 == 0 = 1
        ExpectEq(eqzFunc, [b.loadInt(0)], "1")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Float Comparison Operations
    func testf64ComparisonOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per compare operator.
        let module = b.buildWasmModule { wasmModule in
            for compOp in WasmFloatCompareOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf64, .wasmf64] => .wasmi32) { function, args in
                    let result = function.wasmf64CompareOp(args[0], args[1], using: compOp)
                    function.wasmReturn(result)
                }
            }
        }

        let eqFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Eq.rawValue))
        let neFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Ne.rawValue))
        let ltFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Lt.rawValue))
        let gtFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Gt.rawValue))
        let leFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Le.rawValue))
        let geFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Ge.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1.9 == 1.9 = 1
        ExpectEq(eqFunc, [b.loadFloat(1.9), b.loadFloat(1.9)], "1")

        // 1.9 != 1.9 = 0
        ExpectEq(neFunc, [b.loadFloat(1.9), b.loadFloat(1.9)], "0")

        // -1.9 < -2 = 0
        ExpectEq(ltFunc, [b.loadFloat(-1.9), b.loadFloat(-2)], "0")

        // -1.9 > -2 = 1
        ExpectEq(gtFunc, [b.loadFloat(-1.9), b.loadFloat(-2)], "1")

        // -1.9 <= -1.9 = 1
        ExpectEq(leFunc, [b.loadFloat(-1.9), b.loadFloat(-1.9)], "1")

        // -1 >= 2.1 = 0
        ExpectEq(geFunc, [b.loadFloat(-1), b.loadFloat(2.1)], "0")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testf32ComparisonOperations() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per compare operator.
        let module = b.buildWasmModule { wasmModule in
            for compOp in WasmFloatCompareOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf32, .wasmf32] => .wasmi32) { function, args in
                    let result = function.wasmf32CompareOp(args[0], args[1], using: compOp)
                    function.wasmReturn(result)
                }
            }
        }

        let eqFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Eq.rawValue))
        let neFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Ne.rawValue))
        let ltFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Lt.rawValue))
        let gtFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Gt.rawValue))
        let leFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Le.rawValue))
        let geFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Ge.rawValue))

        let modVar = module.getModuleVariable()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { function, arguments, output in
            let result = b.callMethod(function, on: modVar, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1.9 == 1.9 = 1
        ExpectEq(eqFunc, [b.loadFloat(1.9), b.loadFloat(1.9)], "1")

        // 1.9 != 1.9 = 0
        ExpectEq(neFunc, [b.loadFloat(1.9), b.loadFloat(1.9)], "0")

        // -1.9 < -2 = 0
        ExpectEq(ltFunc, [b.loadFloat(-1.9), b.loadFloat(-2)], "0")

        // -1.9 > -2 = 1
        ExpectEq(gtFunc, [b.loadFloat(-1.9), b.loadFloat(-2)], "1")

        // -1.9 <= -1.9 = 1
        ExpectEq(leFunc, [b.loadFloat(-1.9), b.loadFloat(-1.9)], "1")

        // -1 >= 2.1 = 0
        ExpectEq(geFunc, [b.loadFloat(-1), b.loadFloat(2.1)], "0")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }
}
