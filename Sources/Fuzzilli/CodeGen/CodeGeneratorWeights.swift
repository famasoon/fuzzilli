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

/// Default weights for the builtin code generators.
public let codeGeneratorWeights: [String: Int] = [
    // 基本的なコードジェネレータ
    "ThisGenerator": 10,
    "IntegerGenerator": 20,
    "RegExpGenerator": 5,
    "BigIntGenerator": 10,
    "FloatGenerator": 10,
    "StringGenerator": 10,
    "BooleanGenerator": 2,
    "UndefinedGenerator": 1,
    "NullGenerator": 1,
    "ArrayGenerator": 10,
    "FloatArrayGenerator": 10,
    "IntArrayGenerator": 10,
    "TypedArrayGenerator": 20,
    "BuiltinObjectInstanceGenerator": 10,
    "ObjectBuilderFunctionGenerator": 10,
    "ObjectConstructorGenerator": 10,
    "ClassDefinitionGenerator": 20,
    "TrivialFunctionGenerator": 10,

    // Regular code generators
    "ThisGenerator": 3,
    "ArgumentsAccessGenerator": 3,
    "FunctionWithArgumentsAccessGenerator": 2,
    "BuiltinGenerator": 10,
    "BuiltinOverwriteGenerator": 3,
    "LoadNewTargetGenerator": 3,
    "DisposableVariableGenerator": 5,
    "AsyncDisposableVariableGenerator": 5,

    // Object and property generators
    "ObjectLiteralGenerator": 10,
    "ObjectLiteralPropertyGenerator": 20,
    "ObjectLiteralElementGenerator": 5,
    "ObjectLiteralMethodGenerator": 10,
    "ObjectLiteralGetterGenerator": 5,
    "ObjectLiteralSetterGenerator": 5,
    "ObjectLiteralComputedPropertyGenerator": 5,
    "ObjectLiteralSpreadGenerator": 3,
    "PropertyRetrievalGenerator": 30,
    "PropertyAssignmentGenerator": 30,
    "PropertyUpdateGenerator": 15,
    "ComputedPropertyRetrievalGenerator": 20,
    "ComputedPropertyAssignmentGenerator": 20,
    "ComputedPropertyUpdateGenerator": 10,
    "MethodCallGenerator": 20,
    "ComputedMethodCallGenerator": 10,
    "PropertyRemovalGenerator": 5,
    "ElementRetrievalGenerator": 20,
    "ElementAssignmentGenerator": 20,
    "ElementUpdateGenerator": 10,

    // WebAssembly関連のジェネレータ
    "WasmGenerator": 40,                     // 基本的なWASM操作の重みを下げて安定性を向上
    "WasmMemoryOperationsGenerator": 35,     // メモリ操作の重みを調整
    "WasmStructGenerator": 35,               // 構造体操作の重みを調整
    "WasmTableGenerator": 30,                // テーブル操作の優先度を下げる
    "WasmArrayGenerator": 35,                // 配列操作は中程度の重みを維持
    "WasmGlobalGenerator": 30,               // グローバル変数の重みを調整
    "WasmMemoryBoundaryTest": 25,           // メモリ境界テストの頻度を下げる
    "WasmConcurrentAccessTest": 20,         // 並行アクセステストの頻度を下げる
    "WasmTypeConversionTest": 30,           // 型変換テストの重みを調整
    "WasmMemoryFuzzer": 40,                // メモリファジングは重要なので維持
    "WasmSIMDFuzzer": 35,                 // SIMDテストの重みを調整
    "SimpleWasmPromiseGenerator": 30,      // Promise APIテストの頻度を調整
    "WasmJSPIExploitGenerator": 35,       // JSPIエクスプロイトの重みを調整
    "RandomWasmBytesGenerator": 35,       // ランダムバイト列生成の重みを調整
    "RandomWasmValuesGenerator": 40,       // ランダム値生成
    "MaglevOptimizationGenerator": 35,    // Maglev最適化の重みを調整
    "WasmFuzzer": 45,                    // 基本的なファジングは重要なので高めに維持
    "ComplexWasmFuzzer": 40,             // 複雑なファジングの重みを調整
    "ValueSerializerFuzzer": 35,         // シリアライザの重みを調整
    "RegExpFuzzer": 35,                  // 正規表現ファジングの重みを調整
    "MapTransitionFuzzer": 35,           // マップ遷移の重みを調整

    // Special generators
    "WellKnownPropertyLoadGenerator": 5,
    "WellKnownPropertyStoreGenerator": 5,
    "PrototypeAccessGenerator": 10,
    "PrototypeOverwriteGenerator": 10,
    "CallbackPropertyGenerator": 10,
    "MethodCallWithDifferentThisGenerator": 5,
    "WeirdClassGenerator": 10,
    "ProxyGenerator": 10,
    "LengthChangeGenerator": 5,
    "ElementKindChangeGenerator": 5,
    "PromiseGenerator": 3,
    "EvalGenerator": 3,
    "NumberComputationGenerator": 40,
    "ImitationGenerator": 30,
    "ResizableArrayBufferGenerator": 5,
    "GrowableSharedArrayBufferGenerator": 5,
    "FastToSlowPropertiesGenerator": 10,
    "IteratorGenerator": 5,
    "ConstructWithDifferentNewTargetGenerator": 5,
    "ObjectHierarchyGenerator": 10,
    "ApiConstructorCallGenerator": 15,
    "ApiMethodCallGenerator": 15,
    "ApiFunctionCallGenerator": 15,
    "VoidGenerator": 1,

    // 基本的なコードジェネレータの重みを追加
    "BasicCodeGenerator": 50,
]
