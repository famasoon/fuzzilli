let ValueGenerators1Array: [CodeGenerator] = [
    ValueGenerator("IntegerGenerator") { b, n in
        for _ in 0..<n {
            b.loadInt(b.randomInt())
        }
    },
    // 最初の10個程度のValueGeneratorをここに
] 