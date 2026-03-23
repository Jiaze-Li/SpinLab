import Foundation

struct SpinLabRoutePlanner {
    private struct SubstrateDescriptor {
        var treatment: String?
        var material: String?
        var orientation: String?
    }

    func makeRoutePlan(from parsed: SpinLabDomain.ParsedFilenameHints) -> SpinLabDomain.RoutePlan {
        let folderCandidates = uniquePreservingOrder(parsed.folderDerivedSampleKeys)
        let uniqueFolderSampleKey = folderCandidates.count == 1 ? folderCandidates[0] : nil
        var conflicts: [String] = []

        if folderCandidates.count > 1 {
            conflicts.append("Folder-derived sample keys are non-unique: \(folderCandidates.joined(separator: ", ")).")
        }

        let channelHints = parsed.channelHints
        var resolutions: [SpinLabDomain.RouteChannelResolution] = []
        var unresolvedChannels: [String] = []
        let fileLevelSubstrateTags = parsed.substrateTags

        if channelHints.isEmpty {
            let fallbackSampleKeyInput = parsed.defaultSampleKey ?? uniqueFolderSampleKey
            if let fallbackSampleKeyInput,
               let sampleIdentity = resolvedSampleIdentity(
                from: fallbackSampleKeyInput,
                channelTags: [],
                fileLevelSubstrateTags: fileLevelSubstrateTags
               ) {
                resolutions.append(
                    SpinLabDomain.RouteChannelResolution(
                        channel: "file",
                        sampleKey: sampleIdentity,
                        source: parsed.defaultSampleKey != nil ? "defaultSampleKey+substrate" : "folderDerivedSampleKey+substrate",
                        tags: []
                    )
                )
            } else {
                if fallbackSampleKeyInput != nil {
                    conflicts.append("Missing substrate identity for file-level routing.")
                }
                unresolvedChannels.append("file")
            }
        } else {
            for channelHint in channelHints {
                let resolvedSampleKeyInput = channelHint.sampleID ?? parsed.defaultSampleKey ?? uniqueFolderSampleKey
                let resolved = resolvedSampleKeyInput.flatMap { sampleKeyInput in
                    resolvedSampleIdentity(
                        from: sampleKeyInput,
                        channelTags: channelHint.tags,
                        fileLevelSubstrateTags: fileLevelSubstrateTags
                    )
                }
                let source: String
                if channelHint.sampleID != nil {
                    source = "channelSampleKey+substrate"
                } else if parsed.defaultSampleKey != nil {
                    source = "defaultSampleKey+substrate"
                } else if uniqueFolderSampleKey != nil {
                    source = "folderDerivedSampleKey+substrate"
                } else {
                    source = "unresolved"
                }

                let warning: String?
                if resolved == nil && folderCandidates.count > 1 {
                    warning = "Ambiguous folder-derived sample keys."
                } else if resolved == nil && resolvedSampleKeyInput != nil {
                    warning = "Missing substrate identity."
                } else {
                    warning = nil
                }

                resolutions.append(
                    SpinLabDomain.RouteChannelResolution(
                        channel: channelHint.channel,
                        sampleKey: resolved,
                        source: source,
                        tags: effectiveTags(
                            originalTags: channelHint.tags,
                            sampleKeyInput: resolvedSampleKeyInput,
                            resolvedSampleIdentity: resolved
                        ),
                        warning: warning
                    )
                )

                if resolved == nil {
                    unresolvedChannels.append(channelHint.channel)
                }
            }
        }

        conflicts.append(contentsOf: duplicateChannelConflicts(from: resolutions))

        var grouped: [String: Set<String>] = [:]
        for resolution in resolutions {
            guard let sampleKey = resolution.sampleKey else {
                continue
            }
            grouped[sampleKey, default: []].insert(resolution.channel)
        }

        let targets = grouped
            .map { sampleKey, channels in
                SpinLabDomain.RouteTarget(sampleKey: sampleKey, channels: channels.sorted())
            }
            .sorted { $0.sampleKey < $1.sampleKey }

        let status: SpinLabDomain.RouteStatus
        if targets.isEmpty || !unresolvedChannels.isEmpty || !conflicts.isEmpty {
            status = .reviewRequired
        } else {
            status = .applyReady
        }

        return SpinLabDomain.RoutePlan(
            status: status,
            targets: targets,
            channelResolutions: resolutions,
            unresolvedChannels: uniquePreservingOrder(unresolvedChannels),
            conflicts: uniquePreservingOrder(conflicts)
        )
    }

    func resolvedSampleIdentity(
        from sampleKeyInput: String,
        channelTags: [String],
        fileLevelSubstrateTags: [String]
    ) -> String? {
        if let explicit = explicitSampleIdentity(from: sampleKeyInput) {
            return explicit
        }

        let channelDescriptor = substrateDescriptor(from: channelTags)
        let fileDescriptor = substrateDescriptor(from: fileLevelSubstrateTags)

        let material = channelDescriptor.material ?? fileDescriptor.material
        let orientation = channelDescriptor.orientation ?? fileDescriptor.orientation
        let treatment = channelDescriptor.treatment ?? fileDescriptor.treatment
        let batchKey = sampleKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !batchKey.isEmpty, let material, let orientation else {
            return nil
        }

        var substrate = "\(material)(\(orientation))"
        if let treatment {
            substrate = "\(treatment) \(substrate)"
        }
        return "\(batchKey) - \(substrate)"
    }

    private func explicitSampleIdentity(from sampleKeyInput: String) -> String? {
        let trimmed = sampleKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("-") else {
            return nil
        }

        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        let batchKey = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let substrateRaw = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !batchKey.isEmpty, !substrateRaw.isEmpty else {
            return nil
        }

        let descriptor = substrateDescriptor(from: substrateTokens(from: substrateRaw))
        guard let material = descriptor.material, let orientation = descriptor.orientation else {
            return nil
        }

        var substrate = "\(material)(\(orientation))"
        if let treatment = descriptor.treatment {
            substrate = "\(treatment) \(substrate)"
        }
        return "\(batchKey) - \(substrate)"
    }

    private func effectiveTags(
        originalTags: [String],
        sampleKeyInput: String?,
        resolvedSampleIdentity: String?
    ) -> [String] {
        let descriptor = sampleKeyInput
            .flatMap { explicitSampleIdentity(from: $0) }
            .flatMap { substrateDescriptor(fromSampleIdentity: $0) }
            ?? resolvedSampleIdentity.flatMap { substrateDescriptor(fromSampleIdentity: $0) }

        guard let descriptor else {
            return originalTags
        }

        var tags = originalTags.filter { !isSubstrateRelatedTag($0) }
        if let treatment = descriptor.treatment {
            tags.append(treatment)
        }
        if let material = descriptor.material, let orientation = descriptor.orientation {
            tags.append("\(material)\(orientation)")
        }
        return uniquePreservingOrder(tags)
    }

    private func substrateDescriptor(fromSampleIdentity sampleIdentity: String) -> SubstrateDescriptor? {
        let trimmed = sampleIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }

        let substrateRaw = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !substrateRaw.isEmpty else {
            return nil
        }
        let descriptor = substrateDescriptor(from: substrateTokens(from: substrateRaw))
        guard descriptor.material != nil, descriptor.orientation != nil else {
            return nil
        }
        return descriptor
    }

    private func substrateTokens(from raw: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/|,;"))
        let tokens = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return tokens.isEmpty ? [raw] : tokens
    }

    private func isSubstrateRelatedTag(_ tag: String) -> Bool {
        let normalized = normalizeSubstrateToken(tag)
        if normalized.contains("sto")
            || normalized.contains("ngo")
            || normalized.contains("mao")
            || normalized.contains("hf")
            || normalized.contains("bake")
            || normalized == "o"
            || normalized.contains("origin")
            || normalized.contains("original") {
            return true
        }
        return extractOrientation(from: normalized) != nil
    }

    private func substrateDescriptor(from tags: [String]) -> SubstrateDescriptor {
        var descriptor = SubstrateDescriptor()
        for tag in tags {
            let normalized = normalizeSubstrateToken(tag)
            if descriptor.treatment == nil {
                if normalized.contains("hf") {
                    descriptor.treatment = "HF"
                } else if normalized.contains("bake") {
                    descriptor.treatment = "baked"
                } else if normalized == "o" || normalized.contains("origin") || normalized.contains("original") {
                    descriptor.treatment = "o"
                }
            }

            if descriptor.material == nil {
                if normalized.contains("sto") {
                    descriptor.material = "STO"
                } else if normalized.contains("ngo") {
                    descriptor.material = "NGO"
                } else if normalized.contains("mao") {
                    descriptor.material = "MAO"
                }
            }

            if descriptor.orientation == nil,
               let orientation = extractOrientation(from: normalized) {
                descriptor.orientation = orientation
            }
        }
        return descriptor
    }

    private func normalizeSubstrateToken(_ token: String) -> String {
        token.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
    }

    private func extractOrientation(from normalized: String) -> String? {
        guard let range = normalized.range(of: #"(111|001|110|100)"#, options: .regularExpression) else {
            return nil
        }
        return String(normalized[range])
    }

    private func duplicateChannelConflicts(from resolutions: [SpinLabDomain.RouteChannelResolution]) -> [String] {
        var seen: [String: String] = [:]
        var conflicts: [String] = []

        for resolution in resolutions where resolution.channel != "file" {
            let nextKey = resolution.sampleKey ?? "unresolved"
            if let existing = seen[resolution.channel], existing != nextKey {
                conflicts.append("Channel \(resolution.channel) maps to multiple sample keys (\(existing) and \(nextKey)).")
            } else {
                seen[resolution.channel] = nextKey
            }
        }

        return conflicts
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
