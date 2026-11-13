import Foundation
import Observation
import WinlinkKit

/// The gateway directory: the channel list from the Winlink web service
/// cached on disk, plus the user's favourites.
///
/// Persisted as `gateways.json` next to `contacts.json`. Every mutation
/// saves immediately, like the other stores. When no list has been
/// fetched yet — no key, no locator, offline, first launch — the store
/// serves `GatewayDirectory`, so the connect dialog is never empty.
@MainActor @Observable final class GatewayStore {
    /// Schema version of `gateways.json`; bumped only on a breaking
    /// change, and an unknown version makes the cache be discarded.
    static let schemaVersion = 1

    /// Channels from the web service. Empty until the first successful
    /// refresh — `channels` then falls back to the built-in list.
    private(set) var cached = [GatewayChannel]()
    /// Channel IDs the user starred. User data: never touched by a
    /// refresh, and kept even when a channel drops off the list.
    private(set) var favorites = Set<String>()

    private(set) var lastRefresh: Date?
    private(set) var lastAttempt: Date?
    private(set) var lastError: String?
    /// The locator the cached list was fetched for. A different one
    /// makes the stored distances stale.
    private(set) var cachedGridSquare = ""

    private(set) var isRefreshing = false
    /// Set when the service rejected our key. Winlink can revoke the
    /// token, and a client that keeps knocking is exactly what would
    /// make them; only an explicit user action tries again.
    private(set) var accessDenied = false
    private(set) var consecutiveFailures = 0

    // MARK: Refresh policy
    //
    // The access key comes with the condition that these endpoints be
    // queried sparingly. With ARDOP only and the 24 h rule this works
    // out to roughly one request a day.

    /// A cache younger than this is not refreshed automatically.
    static let refreshInterval: TimeInterval = 24 * 3600
    /// After a failure, wait at least this long before trying again.
    static let minimumBackoff: TimeInterval = 6 * 3600
    static let maximumBackoff: TimeInterval = 24 * 3600

    private let fileURL: URL
    private let service: GatewayWebService?

    /// `apiKey` and `fetch` exist for the tests; the app uses the key
    /// injected at build time and real networking.
    init(
        fileURL: URL, apiKey: String = WebServiceKey.value, fetch: HTTPFetch? = nil
    ) {
        self.fileURL = fileURL
        if apiKey.isEmpty {
            service = nil
        } else {
            let version =
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "dev"
            let config = GatewayWebService.Config(
                userAgent: "Skywave/\(version)",
                minimumRequestSpacing: .seconds(2),
                // Even an explicit user request cannot go past this.
                minimumRefreshInterval: .seconds(3600))
            service = GatewayWebService(
                apiKey: apiKey, config: config,
                fetch: fetch ?? HTTPFetcher.urlSession())
        }
        load()
    }

    /// True when no key was injected at build time. The directory then
    /// stays on the built-in list for good.
    var hasAccessKey: Bool { service != nil }

    // MARK: - Reading

    /// What the app should offer: the cached list, or the built-in
    /// starter channels while there is none.
    var channels: [GatewayChannel] {
        cached.isEmpty ? GatewayDirectory.channels : cached
    }

    /// True while the built-in list is standing in for a real one.
    var usesBuiltinFallback: Bool { cached.isEmpty }

    func channels(for kind: RadioTransportKind) -> [GatewayChannel] {
        sorted(channels.filter { $0.kind == kind })
    }

    /// Favourites first, then by distance (unknown last), then by
    /// gateway and frequency so the order never jitters.
    func sorted(_ channels: [GatewayChannel]) -> [GatewayChannel] {
        channels.sorted { lhs, rhs in
            let leftStarred = favorites.contains(lhs.id)
            let rightStarred = favorites.contains(rhs.id)
            if leftStarred != rightStarred { return leftStarred }

            switch (lhs.distanceKm, rhs.distanceKm) {
            case let (left?, right?) where left != right: return left < right
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }
            if lhs.gateway != rhs.gateway { return lhs.gateway < rhs.gateway }
            return lhs.centerHz < rhs.centerHz
        }
    }

    /// Looks a channel up by ID: cache first, then the built-in list.
    ///
    /// The ID scheme is the same in both, so a stored
    /// `settings.ardopChannelID` keeps resolving after the first
    /// refresh — and still resolves if the cache is later empty.
    func channel(id: String) -> GatewayChannel? {
        cached.first { $0.id == id } ?? GatewayDirectory.channel(id: id)
    }

    /// The short list for the connect dialog's picker: favourites
    /// first, then the nearest. A picker with 200 entries is useless.
    func suggestions(for kind: RadioTransportKind, limit: Int = 12) -> [GatewayChannel] {
        Array(channels(for: kind).prefix(limit))
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    /// Favourites whose channel is no longer listed. Shown greyed out
    /// rather than dropped — a gateway in maintenance must not silently
    /// eat the user's selection.
    var orphanedFavorites: [String] {
        let known = Set(channels.map(\.id))
        return favorites.subtracting(known).sorted()
    }

    // MARK: - Writing

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        save()
    }

    // MARK: - Refresh

    /// Why a refresh is currently not possible, for the window's banner.
    /// nil means it may run.
    func refreshBlockedReason(settings: AppSettingsStore) -> String? {
        if !hasAccessKey {
            return String(localized: "Diese Version enthält keinen Winlink-Zugangsschlüssel.")
        }
        if settings.locator.isEmpty {
            return String(localized: "Kein Locator gesetzt (Einstellungen → Allgemein).")
        }
        if !Maidenhead.isValid(settings.locator) {
            return String(localized: "Der Locator «\(settings.locator)» ist kein gültiger Maidenhead-Locator.")
        }
        if accessDenied {
            return String(localized: "Der Winlink-Zugangsschlüssel wurde abgelehnt.")
        }
        return nil
    }

    /// The earliest moment a refresh would do anything, or nil when one
    /// may run right now.
    var nextAllowedRefresh: Date? {
        if consecutiveFailures > 0, let lastAttempt {
            let delay = min(
                Self.maximumBackoff,
                Self.minimumBackoff * pow(2, Double(consecutiveFailures - 1)))
            let next = lastAttempt.addingTimeInterval(delay)
            if next > .now { return next }
        }
        guard let lastRefresh else { return nil }
        let next = lastRefresh.addingTimeInterval(Self.refreshInterval)
        return next > .now ? next : nil
    }

    /// Fetches the channel list.
    ///
    /// `force` is the user pressing the button: it ignores the 24 h and
    /// the backoff rule, but not the hard hourly limit inside
    /// `GatewayWebService` — that one nobody talks past.
    func refresh(settings: AppSettingsStore, force: Bool) async {
        guard !isRefreshing, let service else { return }
        guard refreshBlockedReason(settings: settings) == nil || (force && !accessDenied)
        else { return }
        guard Maidenhead.isValid(settings.locator) else { return }
        if !force {
            guard settings.gatewayRefreshEnabled, nextAllowedRefresh == nil else { return }
        }

        isRefreshing = true
        defer { isRefreshing = false }
        let attempt = Date.now

        do {
            let miles = Int((Double(settings.gatewayMaxDistanceKm) / 1.609_344).rounded())
            let positions = try await service.proximity(
                gridSquare: settings.locator,
                modes: [.ardop],
                historyHours: 24,
                maxDistanceMiles: miles)

            cached = Self.channels(from: positions, home: settings.locator)
            cachedGridSquare = settings.locator
            lastRefresh = attempt
            lastAttempt = attempt
            lastError = nil
            consecutiveFailures = 0
            save()
        } catch let error as WinlinkServiceError {
            // Our own brake is not a failure: nothing was asked of the
            // service, so neither the cache age nor the backoff moves.
            if case .throttled = error { return }

            lastAttempt = attempt
            lastError = error.description
            consecutiveFailures += 1
            if error.isAccessDenied { accessDenied = true }
            save()
        } catch {
            lastAttempt = attempt
            lastError = error.localizedDescription
            consecutiveFailures += 1
            save()
        }
    }

    /// Clears the access-denied latch so the user can try again after
    /// fixing something.
    func retryAfterAccessDenied() {
        accessDenied = false
        consecutiveFailures = 0
    }

    /// Maps web-service records onto the app's channel type.
    ///
    /// Distance and bearing are recomputed locally instead of taken
    /// from the service: the cache outlives a locator change, and the
    /// service rounds to whole statute miles.
    static func channels(
        from positions: [GatewayPosition], home locator: String
    ) -> [GatewayChannel] {
        let here = try? Maidenhead(locator: locator)

        return positions.compactMap { position in
            guard let kind = transportKind(for: position.queriedMode),
                position.frequencyHz > 0, !position.callsign.isEmpty
            else { return nil }

            var distanceKm: Int?
            var heading: Int?
            if let here, let there = try? Maidenhead(locator: position.gridSquare) {
                distanceKm = Int(here.distanceKm(to: there).rounded())
                heading = Int(here.bearingDegrees(to: there).rounded()) % 360
            } else if position.distanceMiles > 0 {
                // No usable grid: fall back on what the service said.
                distanceKm = Int((Double(position.distanceMiles) * 1.609_344).rounded())
                heading = position.headingDegrees
            }

            return GatewayChannel(
                gateway: position.callsign.uppercased(),
                grid: position.gridSquare.uppercased(),
                kind: kind,
                centerHz: position.frequencyHz,
                bandwidthHz: position.bandwidthHz,
                serviceCode: position.serviceCode,
                distanceKm: distanceKm,
                headingDegrees: heading,
                source: .webService)
        }
    }

    private static func transportKind(
        for mode: GatewayOperatingMode
    ) -> RadioTransportKind? {
        switch mode {
        case .ardop: .ardop
        case .vara: .varaHF
        case .varaFM: .varaFM
        // Packet, Pactor and friends have no transport in Skywave.
        default: nil
        }
    }

    // MARK: - Persistence

    /// Everything optional but `version`, the same rule as
    /// `AppSettingsStore.Persisted`: a field added later must not make
    /// an existing file unreadable.
    private struct Persisted: Codable {
        var version: Int
        var lastRefresh: Date?
        var lastAttempt: Date?
        var lastError: String?
        var gridSquare: String?
        var modes: [String]?
        var maxDistanceKm: Int?
        var channels: [GatewayChannel]?
        var favorites: [String]?
        var consecutiveFailures: Int?
        var accessDenied: Bool?
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(Persisted.self, from: data),
            decoded.version <= Self.schemaVersion
        else {
            // Missing, corrupt or newer than we understand: start from
            // the built-in list rather than fail. Never throws upwards.
            return
        }
        cached = decoded.channels ?? []
        favorites = Set(decoded.favorites ?? [])
        lastRefresh = decoded.lastRefresh
        lastAttempt = decoded.lastAttempt
        lastError = decoded.lastError
        cachedGridSquare = decoded.gridSquare ?? ""
        consecutiveFailures = decoded.consecutiveFailures ?? 0
        accessDenied = decoded.accessDenied ?? false
    }

    func save() {
        let snapshot = Persisted(
            version: Self.schemaVersion,
            lastRefresh: lastRefresh,
            lastAttempt: lastAttempt,
            lastError: lastError,
            gridSquare: cachedGridSquare,
            modes: [GatewayOperatingMode.ardop.rawValue],
            maxDistanceKm: nil,
            channels: cached,
            favorites: favorites.sorted(),
            consecutiveFailures: consecutiveFailures,
            accessDenied: accessDenied)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
}
