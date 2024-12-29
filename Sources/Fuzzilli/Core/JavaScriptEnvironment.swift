// WebAssembly関連のビルトインを追加
builtins["WebAssembly"] = .object(withMethods: ["compile", "validate", "instantiate"])
builtins["WebAssembly.Module"] = .constructor()
builtins["WebAssembly.Instance"] = .constructor()
builtins["WebAssembly.Memory"] = .constructor()
builtins["WebAssembly.Table"] = .constructor()
builtins["WebAssembly.Global"] = .constructor() 