//
//  StatusTableViewController+Carbs.swift
//  Loop
//
//  Offers meals logged in the Carbs app. A suggestion only ever opens the normal carb entry
//  screen filled in; the user reviews it, sees the bolus recommendation and confirms as usual.
//

import UIKit
import LoopKit

extension StatusTableViewController {
    /// Suggestions the user chose "Later" for, asked again the next time Loop opens.
    private static var deferredCarbsSuggestionIDs = Set<String>()

    /// Call when Loop becomes active again, so "Later" means "next time I open Loop".
    func resetDeferredCarbsSuggestions() {
        Self.deferredCarbsSuggestionIDs.removeAll()
    }

    /// Asks about the oldest recent meal from Carbs, if the main screen is showing and idle.
    func checkCarbsSuggestions() {
        guard onscreen, presentedViewController == nil, onboardingManager.isComplete else { return }
        guard let suggestion = CarbsSuggestionStore.shared.offerable()
            .first(where: { !Self.deferredCarbsSuggestionIDs.contains($0.id) }) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let duplicate = await possibleDuplicate(of: suggestion)
            guard onscreen, presentedViewController == nil else { return }

            let alert = UIAlertController(title: NSLocalizedString("Meal from Carbs", comment: "Title of the prompt offering a meal logged in the Carbs app"),
                                          message: message(for: suggestion, duplicate: duplicate),
                                          preferredStyle: .alert)
            let review = UIAlertAction(title: NSLocalizedString("Review in Loop", comment: "Opens the carb entry screen filled in from Carbs"), style: .default) { [weak self] _ in
                self?.presentCarbEntryScreen(nil, suggestion: suggestion)
            }
            alert.addAction(review)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Dismiss", comment: "Dismisses a meal offered by Carbs"), style: .destructive) { _ in
                CarbsSuggestionStore.shared.mark(suggestion.id, as: .dismissed)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Later", comment: "Asks about a Carbs meal again next time Loop opens"), style: .cancel) { _ in
                Self.deferredCarbsSuggestionIDs.insert(suggestion.id)
            })
            alert.preferredAction = review
            present(alert, animated: true)
        }
    }

    /// Opens a suggestion linked from Carbs ("Send to Loop").
    func presentCarbsSuggestion(id: String) {
        guard let suggestion = CarbsSuggestionStore.shared.suggestion(id: id) else {
            let alert = UIAlertController(title: NSLocalizedString("Meal not available", comment: "Title when a Carbs meal can no longer be opened"),
                                          message: NSLocalizedString("This meal from Carbs was already handled or is too old to add.", comment: "Message when a Carbs meal can no longer be opened"),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            present(alert, animated: true)
            return
        }
        presentCarbEntryScreen(nil, suggestion: suggestion)
    }

    /// Fills in the carb entry screen from a suggestion and marks it as reviewed.
    func apply(_ suggestion: CarbsMealSuggestion, to viewModel: CarbEntryViewModel) {
        viewModel.time = suggestion.startDate
        viewModel.carbsQuantity = suggestion.carbs
        viewModel.foodType = suggestion.mealName
        viewModel.usesCustomFoodType = true
        viewModel.absorptionTime = suggestion.absorptionTime
        viewModel.absorptionTimeWasEdited = true
        CarbsSuggestionStore.shared.mark(suggestion.id, as: .reviewed)
    }

    private func message(for suggestion: CarbsMealSuggestion, duplicate: StoredCarbEntry?) -> String {
        let time = DateFormatter.localizedString(from: suggestion.startDate, dateStyle: .none, timeStyle: .short)
        let hours = Double(suggestion.absorptionMinutes) / 60
        var lines = [
            String(format: NSLocalizedString("%1$@ · %2$@ g carbs", comment: "Meal name and grams of carbs from Carbs"),
                   suggestion.mealName, suggestion.carbs.formatted(.number.precision(.fractionLength(0...1)))),
            String(format: NSLocalizedString("Eaten %1$@ · absorption %2$@ hr", comment: "Time eaten and absorption hours from Carbs"),
                   time, hours.formatted(.number.precision(.fractionLength(0...1)))),
        ]
        if !suggestion.foods.isEmpty {
            lines.append(suggestion.foods.prefix(4).joined(separator: ", ") + (suggestion.foods.count > 4 ? "…" : ""))
        }
        if let duplicate {
            let grams = duplicate.quantity.doubleValue(for: .gram).formatted(.number.precision(.fractionLength(0...1)))
            let when = DateFormatter.localizedString(from: duplicate.startDate, dateStyle: .none, timeStyle: .short)
            lines.append("")
            lines.append(String(format: NSLocalizedString("Loop already has %1$@ g at %2$@. This may be a duplicate.", comment: "Warning that a Carbs meal may already be entered"), grams, when))
        }
        return lines.joined(separator: "\n")
    }

    /// A carb entry already in Loop close in time and size to the suggestion.
    private func possibleDuplicate(of suggestion: CarbsMealSuggestion) async -> StoredCarbEntry? {
        let window: TimeInterval = 30 * 60
        let entries = (try? await carbStore.getCarbEntries(start: suggestion.startDate.addingTimeInterval(-window),
                                                            end: suggestion.startDate.addingTimeInterval(window))) ?? []
        let tolerance = max(5, suggestion.carbs * 0.15)
        return entries.first { abs($0.quantity.doubleValue(for: .gram) - suggestion.carbs) <= tolerance }
    }
}
