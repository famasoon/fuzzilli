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
    // Value generators
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
    "WasmGenerator": 50,                     // 基本的なWASM操作
    "WasmMemoryOperationsGenerator": 40,     // メモリ操作
    "WasmStructGenerator": 40,               // 構造体操作
    "WasmTableGenerator": 40,                // テーブル操作
    "WasmArrayGenerator": 40,                // 配列操作
    "WasmGlobalGenerator": 40,               // グローバル変数
    "WasmMemoryBoundaryTest": 30,           // メモリ境界テスト
    "WasmConcurrentAccessTest": 25,         // 並行アクセステスト
    "WasmTypeConversionTest": 35,           // 型変換テスト
    "WasmMemoryFuzzer": 45,                // メモリファジング
    "WasmMemoryGenerator": 40,             // メモリ生成
    "WasmSIMDFuzzer": 45,                 // SIMDテスト
    "SimpleWasmPromiseGenerator": 35,       // Promise APIテスト
    "WasmJSPIExploitGenerator": 45,        // JSPIエクスプロイト
    "RandomWasmBytesGenerator": 40,        // ランダムバイト列
    "RandomWasmValuesGenerator": 40,       // ランダム値生成
    "MaglevOptimizationGenerator": 40,     // Maglev最適化
    "WasmFuzzer": 50,                     // 基本的なファジング
    "ComplexWasmFuzzer": 50,              // 複雑なファジング
    "ValueSerializerFuzzer": 40,          // シリアライザ
    "RegExpFuzzer": 40,                   // 正規表現
    "MapTransitionFuzzer": 40,            // マップ遷移

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
    "VoidGenerator": 1
]
