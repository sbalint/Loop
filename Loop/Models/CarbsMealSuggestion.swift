//
//  CarbsMealSuggestion.swift
//  Loop
//
//  Meals offered by the Carbs app (https://github.com/sbalint/Carbs) through Loop's App Group.
//  Loop only reads them to fill in its carb entry screen; nothing is saved without the user
//  confirming there. The file format is shared with Carbs/Loop/LoopMealSuggestion.swift.
//

import Foundation
import os.log

struct CarbsMealSuggestion: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        /// Waiting for the user.
        case pending
        /// Opened in the carb entry screen (the user may still have cancelled there).
        case reviewed
        /// Dismissed without opening.
        case dismissed
    }

    var id: String
    var groupKey: String
    var mealName: String
    /// When the meal was eaten.
    var startDate: Date
    /// Grams of carbohydrate.
    var carbs: Double
    var absorptionMinutes: Int
    var foods: [String]
    var entryIDs: [String]
    var status: Status
    var updatedAt: Date
    var handledAt: Date?

    var absorptionTime: TimeInterval { TimeInterval(absorptionMinutes * 60) }
}

private struct CarbsSuggestionFile: Codable {
    var version = 1
    var suggestions: [CarbsMealSuggestion] = []
}

/// Reads and updates the suggestions file Carbs writes into the App Group container.
final class CarbsSuggestionStore {
    static let shared = CarbsSuggestionStore()

    /// The main screen only prompts for meals eaten within this window.
    static let promptMaxAge: TimeInterval = 3 * 60 * 60
    /// A link from Carbs can open meals up to this old (Carbs stops offering after 6 hours).
    static let linkMaxAge: TimeInterval = 6 * 60 * 60
    /// Allows for small clock differences or a meal logged a few minutes ahead.
    static let maxFuture: TimeInterval = 15 * 60

    private let log = OSLog(category: "CarbsSuggestionStore")

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Bundle.main.appGroupSuiteName)?
            .appendingPathComponent("Carbs/meal-suggestions.json")
    }

    /// Pending meals eaten recently enough to offer, oldest first.
    func offerable(now: Date = Date(), maxAge: TimeInterval = CarbsSuggestionStore.promptMaxAge) -> [CarbsMealSuggestion] {
        read().suggestions
            .filter { $0.status == .pending && $0.carbs > 0 && isTimely($0, now: now, maxAge: maxAge) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// A pending suggestion by ID, if it is still recent enough to use.
    func suggestion(id: String, now: Date = Date()) -> CarbsMealSuggestion? {
        offerable(now: now, maxAge: CarbsSuggestionStore.linkMaxAge).first { $0.id == id }
    }

    func mark(_ id: String, as status: CarbsMealSuggestion.Status, now: Date = Date()) {
        guard let url = fileURL else { return }
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { url in
            var file = decode(url)
            guard let index = file.suggestions.firstIndex(where: { $0.id == id }) else { return }
            file.suggestions[index].status = status
            file.suggestions[index].handledAt = now
            do {
                try encoder.encode(file).write(to: url, options: .atomic)
            } catch {
                log.error("Could not update Carbs suggestion: %{public}@", String(describing: error))
            }
        }
        if let coordinatorError {
            log.error("Could not coordinate Carbs suggestions: %{public}@", String(describing: coordinatorError))
        }
    }

    private func isTimely(_ suggestion: CarbsMealSuggestion, now: Date, maxAge: TimeInterval) -> Bool {
        suggestion.startDate >= now.addingTimeInterval(-maxAge) && suggestion.startDate <= now.addingTimeInterval(CarbsSuggestionStore.maxFuture)
    }

    private func read() -> CarbsSuggestionFile {
        guard let url = fileURL else { return CarbsSuggestionFile() }
        var result = CarbsSuggestionFile()
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            result = decode(url)
        }
        return result
    }

    private func decode(_ url: URL) -> CarbsSuggestionFile {
        guard let data = try? Data(contentsOf: url) else { return CarbsSuggestionFile() }
        do {
            return try decoder.decode(CarbsSuggestionFile.self, from: data)
        } catch {
            log.error("Could not read Carbs suggestions: %{public}@", String(describing: error))
            return CarbsSuggestionFile()
        }
    }
}
