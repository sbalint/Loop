//
//  EstimatedParametersViewController.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit

protocol EstimatedParametersViewControllerDelegate: class {
    func estimatedParametersViewControllerDidChangeValue(_ controller: EstimatedParametersViewController)
}


class EstimatedParametersViewController: ChartsTableViewController, IdentifiableClass {

    var glucoseUnit: HKUnit {
        get {
            return charts.glucoseUnit
        }
        set {
            charts.glucoseUnit = newValue

            refreshContext = true
            if visible && active {
                reloadData()
            }
        }
    }

    weak var delegate: EstimatedParametersViewControllerDelegate?
    
    private var initialInsulinModel: InsulinModel?

    /// The currently-selected model.
    var insulinModel: InsulinModel? {
        didSet {
            if let newValue = insulinModel as? WalshInsulinModel {
                allModels[walshModelIndex] = newValue
            }

            refreshContext = true
            reloadData()
        }
    }

    override func glucoseUnitDidChange() {
        refreshContext = true
    }

    /// The sensitivity (in glucose units) to use for demonstrating the model
    var insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue<Double>(startTime: 0, value: 40)])!

    fileprivate let walshModelIndex = 0

    private var allModels: [InsulinModel] = [
        WalshInsulinModel(actionDuration: .hours(6)),
        ExponentialInsulinModelPreset.humalogNovologAdult,
        ExponentialInsulinModelPreset.humalogNovologChild,
        ExponentialInsulinModelPreset.fiasp
    ]

    private var selectedModelIndex: Int? {
        switch insulinModel {
        case .none:
            return nil
        case is WalshInsulinModel:
            return walshModelIndex
        case let selectedModel as ExponentialInsulinModelPreset:
            for index in 1..<allModels.count {
                if selectedModel == (allModels[index] as! ExponentialInsulinModelPreset) {
                    return index
                }
            }
        default:
            assertionFailure("Unknown insulin model: \(String(describing: insulinModel))")
        }

        return nil
    }

    private var refreshContext = true

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 91
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Record the configured insulinModel for change tracking
        initialInsulinModel = insulinModel
    }

    override func viewWillDisappear(_ animated: Bool) {
        // Notify observers if the model changed since viewDidAppear
        switch (initialInsulinModel, insulinModel) {
        case let (lhs, rhs) as (WalshInsulinModel, WalshInsulinModel):
            if lhs != rhs {
                delegate?.estimatedParametersViewControllerDidChangeValue(self)
            }
        case let (lhs, rhs) as (ExponentialInsulinModelPreset, ExponentialInsulinModelPreset):
            if lhs != rhs {
                delegate?.estimatedParametersViewControllerDidChangeValue(self)
            }
        default:
            delegate?.estimatedParametersViewControllerDidChangeValue(self)
        }

        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        refreshContext = true

        super.viewWillTransition(to: size, with: coordinator)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        refreshContext = true
    }

    // MARK: - ChartsTableViewController

    override func reloadData(animated: Bool = true) {
        if active && visible && refreshContext {
            refreshContext = false
            charts.startDate = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .strict, direction: .backward) ?? Date()
            
            // try dose effect
            let date = Date()
            //let basalRates: BasalRateSchedule?
            let dose1 = DoseEntry(type: .tempBasal, startDate: date, endDate: date.addingTimeInterval(.hours(2)), value: 1.0, unit: .unitsPerHour)
            //let scheduledBasalRate = HKQuantity(unit: DoseUnit.unitsPerHour, doubleValue: 0.5)
            let insulinModel = ExponentialInsulinModelPreset.humalogNovologAdult
            //let testDose = DoseEntry(suspendDate: date)
            let testDose = DoseEntry(type: .tempBasal, startDate: date, endDate: date.addingTimeInterval(.hours(2)), value: 1.0, unit: .unitsPerHour)
            //testDose.scheduledBasalRate = HKQuantity(unit: DoseEntry.unitsPerHour, doubleValue: 0.5)
            //scheduledBasalRate: HKQuantity(unit: DoseEntry.unitsPerHour, doubleValue: 0.5))
            let unitsPerHour = testDose.netBasalUnitsPerHour
            let testEffects = [testDose].glucoseEffects(insulinModel: insulinModel, insulinSensitivity: insulinSensitivitySchedule)
            let initialGlucoseQuantity = HKQuantity(unit: glucoseUnit, doubleValue: 200)
            let initialGlucoseSample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!, quantity: initialGlucoseQuantity, start: date, end: date)
            let testGlucose = LoopMath.predictGlucose(startingAt: initialGlucoseSample, effects: testEffects)
            
            let basal = DoseEntry(type: .bolus, startDate: charts.startDate, value: 2, unit: .units)
            let selectedModelIndex = self.selectedModelIndex

            let startingGlucoseQuantity = HKQuantity(unit: glucoseUnit, doubleValue: 200)
            let endingGlucoseQuantity = HKQuantity(unit: glucoseUnit, doubleValue: 100)
            let startingGlucoseSample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!, quantity: startingGlucoseQuantity, start: charts.startDate, end: charts.startDate)

            charts.glucoseDisplayRange = (min: endingGlucoseQuantity, max: startingGlucoseQuantity)

            var unselectedModelValues = [[GlucoseValue]]()

            for (index, model) in allModels.enumerated() {
                let effects = [basal].glucoseEffects(insulinModel: model, insulinSensitivity: insulinSensitivitySchedule)
                let values = LoopMath.predictGlucose(startingAt: startingGlucoseSample, effects: effects)
                let glucoseFirst = values.first?.quantity.doubleValue(for: glucoseUnit)
                let glucoseLast = values.last?.quantity.doubleValue(for: glucoseUnit)

                if selectedModelIndex == index {
                    charts.setSelectedInsulinModelValues(values)
                } else {
                    unselectedModelValues.append(values)
                }
            }

            charts.setUnselectedInsulinModelValues(unselectedModelValues)

            // Rendering
            charts.prerender()

            for case let cell as ChartTableViewCell in self.tableView.visibleCells {
                cell.reloadChart()
            }
        }
    }

    // MARK: - UITableViewDataSource

    fileprivate enum Section: Int {
        case charts
        case models

        static let count = 2
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .charts:
            return 1
        case .models:
            return allModels.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .charts:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className, for: indexPath) as! ChartTableViewCell
            cell.contentView.layoutMargins.left = tableView.separatorInset.left
            cell.chartContentView.chartGenerator = { [weak self] (frame) in
                return self?.charts.insulinModelChartWithFrame(frame)?.view
            }

            return cell
        case .models:
            let cell = tableView.dequeueReusableCell(withIdentifier: TitleSubtitleTextFieldTableViewCell.className, for: indexPath) as! TitleSubtitleTextFieldTableViewCell
            let isSelected = selectedModelIndex == indexPath.row
            cell.tintColor = isSelected ? nil : .clear
            cell.textField.isEnabled = isSelected

            switch allModels[indexPath.row] {
            case let model as WalshInsulinModel:
                configureCell(cell, duration: nil)

                cell.titleLabel.text = model.title
                cell.subtitleLabel.text = model.subtitle
            case let model as ExponentialInsulinModelPreset:
                configureCell(cell, duration: nil)

                cell.titleLabel.text = model.title
                cell.subtitleLabel.text = model.subtitle
            case let model:
                assertionFailure("Unknown insulin model: \(model)")
            }

            return cell
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard case .models? = Section(rawValue: indexPath.section) else {
            return
        }

        insulinModel = allModels[indexPath.row]
        let selectedIndex = selectedModelIndex

        for index in 0..<allModels.count {
            guard let cell = tableView.cellForRow(at: IndexPath(row: index, section: Section.models.rawValue)) as? TitleSubtitleTextFieldTableViewCell else {
                continue
            }

            let isSelected = selectedIndex == index
            cell.tintColor = isSelected ? nil : .clear
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}


// MARK: - no duration editing here, no text fileds
fileprivate extension EstimatedParametersViewController {
    func configureCell(_ cell: TitleSubtitleTextFieldTableViewCell, duration: TimeInterval?) {
            cell.textField.isHidden = true
            cell.textField.delegate = nil
            cell.textField.tintColor = nil
            cell.textField.inputView = nil
            cell.textField.text = nil
    }
}
