import Foundation

struct WatchlistEntry: Codable {
    var costPrice: Double
    var holdingShares: Double
}

struct Watchlist: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var entries: [String: WatchlistEntry] = [:]  // stockId -> entry
}
