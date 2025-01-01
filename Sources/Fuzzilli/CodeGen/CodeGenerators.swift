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

//
// Code generators.
//
// These insert one or more instructions into a program.
//

// 各ジェネレータグループを別ファイルから読み込み
private let ValueGenerators1 = ValueGenerators1Array
private let ValueGenerators2 = ValueGenerators2Array
private let ValueGenerators = ValueGenerators1 + ValueGenerators2

private let BasicCodeGenerators1 = BasicCodeGenerators1Array
private let BasicCodeGenerators2 = BasicCodeGenerators2Array
private let BasicCodeGenerators = BasicCodeGenerators1 + BasicCodeGenerators2

private let ObjectGenerators1 = ObjectGenerators1Array
private let ObjectGenerators2 = ObjectGenerators2Array
private let ObjectGenerators = ObjectGenerators1 + ObjectGenerators2

private let WasmGenerators1 = WasmGenerators1Array
private let WasmGenerators2 = WasmGenerators2Array
private let WasmGenerators = WasmGenerators1 + WasmGenerators2

// メインの配列を結合して作成
public let CodeGenerators: [CodeGenerator] = 
    ValueGenerators + 
    BasicCodeGenerators + 
    ObjectGenerators + 
    WasmGenerators

extension Array where Element == CodeGenerator {
    public func get(_ name: String) -> CodeGenerator {
        for generator in self {
            if generator.name == name {
                return generator
            }
        }
        fatalError("Unknown code generator \(name)")
    }
}
