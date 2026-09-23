import Foundation

/// Favorite apps as an ordered key list, pinned to the top while the search is empty.
///
/// A favorite can also be marked "always on top", which keeps it in a leading block once a query is
/// typed and nothing matches it. The Actions menu is the one place either flag is set.
@MainActor
@Observable
final class FavoritesStore {
    private let defaults = UserDefaults.standard
    private let key = "favoriteApps"
    private let alwaysOnTopKey = "alwaysOnTopFavorites"

    private(set) var keys: [String]
    /// Favorites that stay pinned while the query is non-empty; always a subset of `keys`.
    private(set) var alwaysOnTopKeys: Set<String>
    /// AppIndex includes this in its result key, invalidating a list when the pinning changes.
    private(set) var revision = 0

    init() {
        keys = defaults.stringArray(forKey: key) ?? []
        alwaysOnTopKeys = Set(defaults.stringArray(forKey: alwaysOnTopKey) ?? [])
        // A key that is no longer a favorite cannot stay always-on-top.
        alwaysOnTopKeys.formIntersection(keys)
    }

    func key(for app: AppEntry) -> String { app.preferenceKey }

    func isFavorite(_ app: AppEntry) -> Bool { keys.contains(key(for: app)) }

    func isAlwaysOnTop(_ app: AppEntry) -> Bool { alwaysOnTopKeys.contains(key(for: app)) }

    /// Replace the whole favorites list at once (used when importing a settings backup).
    func replace(keys newKeys: [String], alwaysOnTop: [String] = []) {
        keys = newKeys
        alwaysOnTopKeys = Set(alwaysOnTop).intersection(newKeys)
        commit()
    }

    func remove(keys removedKeys: Set<String>) {
        guard !removedKeys.isEmpty else { return }
        let updated = keys.filter { !removedKeys.contains($0) }
        guard updated != keys else { return }
        keys = updated
        alwaysOnTopKeys.subtract(removedKeys)
        commit()
    }

    func toggle(_ app: AppEntry) {
        let k = key(for: app)
        if let index = keys.firstIndex(of: k) {
            keys.remove(at: index)
            alwaysOnTopKeys.remove(k)
        } else {
            keys.append(k)
        }
        commit()
    }

    /// Only a favorite can stay on top; clearing the flag leaves the favorite itself alone.
    func setAlwaysOnTop(_ flag: Bool, for app: AppEntry) {
        let k = key(for: app)
        guard keys.contains(k) else { return }
        let updated = flag ? alwaysOnTopKeys.union([k]) : alwaysOnTopKeys.subtracting([k])
        guard updated != alwaysOnTopKeys else { return }
        alwaysOnTopKeys = updated
        commit()
    }

    /// The pair comes from the visible order, so hidden entries keep their slots.
    func exchange(_ first: String, with second: String) {
        guard let a = keys.firstIndex(of: first), let b = keys.firstIndex(of: second), a != b else {
            return
        }
        keys.swapAt(a, b)
        commit()
    }

    private func commit() {
        revision &+= 1
        defaults.set(keys, forKey: key)
        defaults.set(Array(alwaysOnTopKeys).sorted(), forKey: alwaysOnTopKey)
    }

    /// Split `apps` into favorites (in stored order) and the rest (order preserved).
    func ordered(_ apps: [AppEntry]) -> (favorites: [AppEntry], rest: [AppEntry]) {
        guard !keys.isEmpty else { return ([], apps) }
        let byKey = Dictionary(
            apps.map { (key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let favorites = keys.compactMap { byKey[$0] }
        let favoriteKeys = Set(keys)
        let rest = apps.filter { !favoriteKeys.contains(key(for: $0)) }
        return (favorites, rest)
    }

    /// The always-on-top favorites present in `apps`, in favorite order.
    func alwaysOnTop(in apps: [AppEntry]) -> [AppEntry] {
        guard !alwaysOnTopKeys.isEmpty else { return [] }
        let byKey = Dictionary(
            apps.map { (key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        return keys.compactMap { alwaysOnTopKeys.contains($0) ? byKey[$0] : nil }
    }
}
