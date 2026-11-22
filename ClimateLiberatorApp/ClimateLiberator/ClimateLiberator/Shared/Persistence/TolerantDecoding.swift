import Foundation

// Saved files decode with defaults for missing keys, so fields can be added in later
// versions without breaking files written by earlier ones.

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when the key is missing.
    nonisolated func value<T: Decodable>(_ key: Key, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
