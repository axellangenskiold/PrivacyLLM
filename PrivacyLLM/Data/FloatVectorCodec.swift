import Foundation

/// Packs embedding vectors into raw little-endian Float32 BLOBs (DR-2).
nonisolated enum FloatVectorCodec {
    static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.stride
        var result = [Float](repeating: 0, count: count)
        _ = result.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return result
    }
}
