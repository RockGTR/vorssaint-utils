// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// Pure helpers for checking and comparing application versions according to
/// Semantic Versioning 2.0.0, handling stable and pre-release (beta, rc, alpha) channels.
enum UpdateServiceSupport {

    static func sha256Matches(_ data: Data, expectedHex: String) -> Bool {
        guard expectedHex.utf8.count == SHA256.byteCount * 2 else { return false }
        let actual = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return actual == expectedHex.lowercased()
    }

    // MARK: - Pre-release Identifier

    enum PrereleaseIdentifier: Comparable, Equatable, CustomStringConvertible {
        case numeric(Int)
        case string(String)

        init(_ raw: String) {
            if let num = Int(raw) {
                self = .numeric(num)
            } else {
                self = .string(raw)
            }
        }

        var description: String {
            switch self {
            case let .numeric(val): return "\(val)"
            case let .string(val): return val
            }
        }

        static func < (lhs: PrereleaseIdentifier, rhs: PrereleaseIdentifier) -> Bool {
            switch (lhs, rhs) {
            case let (.numeric(l), .numeric(r)):
                return l < r
            case let (.string(l), .string(r)):
                return l.localizedStandardCompare(r) == .orderedAscending
            case (.numeric, .string):
                // Numeric identifiers have lower precedence than non-numeric identifiers.
                return true
            case (.string, .numeric):
                return false
            }
        }
    }

    // MARK: - Semantic Version

    struct SemanticVersion: Comparable, Equatable, CustomStringConvertible {
        let major: Int
        let minor: Int
        let patch: Int
        let prerelease: [PrereleaseIdentifier]

        var isPrerelease: Bool { !prerelease.isEmpty }

        var description: String {
            let core = "\(major).\(minor).\(patch)"
            if prerelease.isEmpty { return core }
            return "\(core)-\(prerelease.map(\.description).joined(separator: "."))"
        }

        init?(raw: String) {
            let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))
            guard !cleaned.isEmpty else { return nil }

            // Separate build metadata if present (+build123)
            let withoutBuild = cleaned.components(separatedBy: "+").first ?? cleaned

            let parts = withoutBuild.components(separatedBy: "-")
            let corePart = parts[0]
            let coreNumbers = corePart.components(separatedBy: ".").compactMap { Int($0) }
            guard !coreNumbers.isEmpty else { return nil }

            self.major = coreNumbers.indices.contains(0) ? coreNumbers[0] : 0
            self.minor = coreNumbers.indices.contains(1) ? coreNumbers[1] : 0
            self.patch = coreNumbers.indices.contains(2) ? coreNumbers[2] : 0

            if parts.count > 1 {
                let prereleasePart = parts.dropFirst().joined(separator: "-")
                self.prerelease = prereleasePart
                    .components(separatedBy: ".")
                    .filter { !$0.isEmpty }
                    .map { PrereleaseIdentifier($0) }
            } else {
                self.prerelease = []
            }
        }

        init(major: Int, minor: Int, patch: Int, prerelease: [PrereleaseIdentifier] = []) {
            self.major = major
            self.minor = minor
            self.patch = patch
            self.prerelease = prerelease
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

            // When major, minor, and patch are equal, a pre-release version has lower
            // precedence than a normal (release) version.
            // Example: 1.0.0-beta < 1.0.0
            if lhs.isPrerelease && !rhs.isPrerelease { return true }
            if !lhs.isPrerelease && rhs.isPrerelease { return false }
            if !lhs.isPrerelease && !rhs.isPrerelease { return false }

            // Both have pre-release identifiers: compare each identifier step-by-step
            for (l, r) in zip(lhs.prerelease, rhs.prerelease) {
                if l != r { return l < r }
            }
            return lhs.prerelease.count < rhs.prerelease.count
        }
    }

    // MARK: - Version Comparison

    /// Returns true if `candidate` is a higher semantic version than `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidateVersion = SemanticVersion(raw: candidate) else { return false }
        guard let currentVersion = SemanticVersion(raw: current) else {
            // If current is invalid or dev string, consider candidate newer if candidate is valid
            return true
        }
        return candidateVersion > currentVersion
    }

    // MARK: - Release Candidate Selection

    struct ReleaseCandidate {
        let tagName: String
        let isPrerelease: Bool
        let isDraft: Bool
        let dmgURL: URL?
        let dmgExpectedBytes: Int64?
        let body: String?
        var dmgDigest: String? = nil
    }

    static func personalBuildNumber(_ version: String) -> Int? {
        let parts = version.components(separatedBy: "+personal.")
        guard parts.count == 2, !parts[1].isEmpty,
              parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(parts[1]), number > 0 else { return nil }
        return number
    }

    /// GitHub supplies this digest through its HTTPS release-asset API.
    static func sha256Hex(from digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = String(digest.dropFirst(7)).lowercased()
        guard hex.utf8.count == 64,
              hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return hex
    }

    /// Selects the best update candidate from a list of releases based on channel preferences.
    static func selectUpdate(from candidates: [ReleaseCandidate],
                             currentVersion: String,
                             includeBetas: Bool,
                             personalRepository: String? = nil) -> ReleaseCandidate? {
        if let personalRepository {
            let currentBuild = personalBuildNumber(currentVersion) ?? 0
            return candidates.filter { candidate in
                guard !candidate.isDraft, !candidate.isPrerelease,
                      let number = personalBuildNumber(candidate.tagName), number > currentBuild,
                      sha256Hex(from: candidate.dmgDigest) != nil,
                      let url = candidate.dmgURL, url.scheme == "https", url.host == "github.com",
                      url.path.hasPrefix("/\(personalRepository)/releases/download/") else { return false }
                return true
            }.max { (personalBuildNumber($0.tagName) ?? 0) < (personalBuildNumber($1.tagName) ?? 0) }
        }
        let eligible = candidates.filter { candidate in
            guard !candidate.isDraft else { return false }
            guard candidate.dmgURL != nil else { return false }

            let parsed = SemanticVersion(raw: candidate.tagName)
            let isBeta = candidate.isPrerelease || (parsed?.isPrerelease ?? false)

            if !includeBetas && isBeta {
                return false
            }
            return isNewer(candidate.tagName, than: currentVersion)
        }

        // Sort candidate versions in descending order (highest version first)
        return eligible.sorted { (lhs, rhs) -> Bool in
            guard let vL = SemanticVersion(raw: lhs.tagName),
                  let vR = SemanticVersion(raw: rhs.tagName) else { return false }
            return vL > vR
        }.first
    }
}
