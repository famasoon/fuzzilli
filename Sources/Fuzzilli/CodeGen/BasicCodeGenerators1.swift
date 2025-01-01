let BasicCodeGenerators1Array: [CodeGenerator] = [
    CodeGenerator("ThisGenerator") { b in
        b.loadThis()
    },
    // 最初の10個程度のBasicCodeGeneratorをここに
] 