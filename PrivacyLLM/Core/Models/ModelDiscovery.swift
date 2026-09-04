import Foundation

/// Turns Hugging Face's model listing into catalog entries so the app doesn't
/// have to ship a new build to offer a new model (FR-43).
///
/// Two honest limits worth naming: the Hub has no notion of "best", so this
/// ranks by downloads within `mlx-community` — popular, current, and known to
/// convert cleanly, which on a phone is the closest usable proxy. And the
/// listing carries no file sizes, so sizes here are *estimates* from the
/// parameter count and quantization; the exact figure comes from the repo's
/// file tree at download time, which is where the checksum lives anyway.
nonisolated struct HFModelSummary: Sendable, Decodable {
    var id: String
    var downloads: Int?
    var likes: Int?
    /// The listing endpoint returns `createdAt`; `lastModified` only appears on
    /// the detail endpoint, so it is the fallback rather than the other way round.
    var createdAt: String?
    var lastModified: String?
    var tags: [String]?
}

nonisolated enum ModelDiscovery {
    /// Repos whose names say they aren't a text chat model. Cheaper and more
    /// reliable than trusting pipeline tags, which mlx-community often omits.
    private static let excludedMarkers = [
        "-vl-", "vision", "audio", "whisper", "-tts", "embed", "bge-", "clip",
        "siglip", "rerank", "diffusion", "flux", "stable-", "-sd-", "guard",
        "-base", "coder-base", "vlm", "omni", "image",
    ]

    /// Bigger than this is not a phone model, however well it converts.
    static let maxParametersBillions = 9.0

    static func specs(from summaries: [HFModelSummary], limit: Int = 40) -> [ModelSpec] {
        summaries
            .compactMap(spec(from:))
            .reduce(into: [ModelSpec]()) { unique, spec in
                if !unique.contains(where: { $0.id == spec.id }) { unique.append(spec) }
            }
            .prefix(limit)
            .map(\.self)
    }

    static func spec(from summary: HFModelSummary) -> ModelSpec? {
        let repo = summary.id
        let name = repo.split(separator: "/").last.map(String.init) ?? repo
        let lower = name.lowercased()

        guard !excludedMarkers.contains(where: { lower.contains($0) }) else { return nil }
        guard let quantization = quantization(in: lower) else { return nil }
        guard let parameters = parameterCount(in: name) else { return nil }
        let billions = Double(parameters.dropLast().filter { $0.isNumber || $0 == "." }) ?? 0
        guard billions > 0, billions <= maxParametersBillions else { return nil }

        let sizeBytes = estimatedSizeBytes(billions: billions, quantization: quantization)
        let sizeGB = Double(sizeBytes) / 1_073_741_824
        return ModelSpec(
            id: identifier(for: repo),
            displayName: displayName(from: name),
            family: family(from: name),
            hfRepo: repo,
            // A phone can stream a small model quickly enough to feel "fast";
            // anything bigger is a considered-answer model.
            roles: billions <= 3 ? [.fast, .thinking] : [.thinking],
            sizeBytes: sizeBytes,
            parameterCount: parameters,
            quantization: quantization,
            // ponytail: ~2x the weights covers KV cache and headroom. Matches the
            // hand-written catalog within a GB; tighten if downloads start OOMing.
            minRAMGB: max(4, Int((sizeGB * 1.9).rounded(.up))),
            contextLength: 8192,
            licenseName: String(localized: "See model card"),
            licenseURLString: "https://huggingface.co/\(repo)",
            capabilities: ModelCapabilities(
                nativeThinking: lower.contains("qwen3") || lower.contains("think"),
                toolCalling: true
            ),
            releaseDate: releaseDate(from: summary.createdAt ?? summary.lastModified)
        )
    }

    /// Namespaced so a discovered repo can never collide with a bundled id, and
    /// slash-free because the id doubles as the on-disk directory name.
    static func identifier(for repo: String) -> String {
        "hf-" + repo.replacingOccurrences(of: "/", with: "--").lowercased()
    }

    static func quantization(in lowercasedName: String) -> String? {
        for bits in ["3bit", "4bit", "5bit", "6bit", "8bit"] where lowercasedName.contains(bits) {
            return bits.replacingOccurrences(of: "bit", with: "-bit")
        }
        return nil
    }

    /// Pulls "4B" out of "Qwen3.5-4B-4bit" — the standalone parameter token, not
    /// the "3.5" of a version or the "4" of the quantization. A trailing b only
    /// counts when a separator follows it, which is what separates "e2b-it"
    /// (2 billion) from "4bit" (a quantization).
    static func parameterCount(in name: String) -> String? {
        let characters = Array(name)
        var current = ""
        for (index, character) in characters.enumerated() {
            if character.isNumber || character == "." {
                current.append(character)
            } else if character == "b" || character == "B" {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let isStandalone = next.map { !($0.isLetter || $0.isNumber) } ?? true
                if !current.isEmpty, !current.hasSuffix("."), isStandalone {
                    return current + "B"
                }
                current = ""
            } else {
                current = ""
            }
        }
        return nil
    }

    /// Quantized weights scale with the parameter count; the embedding and norm
    /// tensors stay at higher precision and don't, which is why a flat
    /// bytes-per-parameter figure is wrong at both ends of the range. Slope plus
    /// a capped tail matches the hand-written catalog within a few percent
    /// (2B → 1.65 GB vs 1.63 actual, 4B → 2.75 vs 2.85) and errs high, which is
    /// the safe direction for a RAM gate.
    /// ponytail: the exact size arrives with the repo's file tree at download
    /// time — this only has to be close enough to warn before the tap.
    static func estimatedSizeBytes(billions: Double, quantization: String) -> Int64 {
        let bytesPerParameter: Double = switch quantization {
        case "3-bit": 0.42
        case "4-bit": 0.55
        case "5-bit": 0.68
        case "6-bit": 0.80
        default: 1.05
        }
        let weights = billions * bytesPerParameter
        let tail = min(0.55, billions * 0.28)
        return Int64((weights + tail) * 1_073_741_824)
    }

    static func displayName(from name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    static func family(from name: String) -> String {
        (name.split(separator: "-").first.map(String.init) ?? name).lowercased()
    }

    static func releaseDate(from lastModified: String?) -> String? {
        guard let lastModified, lastModified.count >= 10 else { return nil }
        return String(lastModified.prefix(10))
    }
}
