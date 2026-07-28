import Foundation
import HealthKit

enum HealthKitError: LocalizedError {
    case unavailable
    case invalidRange

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data is not available on this device."
        case .invalidRange:
            return "End time must be after start time."
        }
    }
}

struct WalkEntry: Identifiable {
    let id: String
    let steps: Int
    let distanceMeters: Double
    let kcal: Double
    let writtenAt: Date
    fileprivate let batchID: String?
    fileprivate let fallbackSample: HKQuantitySample?

    var distanceKm: Double { distanceMeters / 1000 }
}

final class HealthKitManager {
    static let shared = HealthKitManager()

    private static let batchIDKey = "com.ifakehealth.batchID"

    private let store = HKHealthStore()

    private let metersPerStep = 0.762
    private let kcalPerStep = 0.04

    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var distanceType: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }
    private var energyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }

    private var sampleTypes: Set<HKQuantityType> {
        [stepType, distanceType, energyType]
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.unavailable
        }
        try await store.requestAuthorization(toShare: sampleTypes, read: sampleTypes)
    }

    /// Splits the walk into several smaller samples spread across `start...end`
    /// with varying pace and small pauses, instead of one suspiciously round
    /// block, so it reads like real pedometer data in the Health app.
    ///
    /// Note: Health's displayed daily total de-duplicates overlapping samples
    /// from different sources rather than summing them, so if the phone
    /// recorded any real steps during the same window, the total shown can
    /// end up lower than what was written. Pick a window with no real activity
    /// (e.g. overnight) to avoid that.
    func writeWalk(steps: Int, start: Date, end: Date) async throws {
        guard steps > 0 else { return }
        guard start < end else { throw HealthKitError.invalidRange }

        let chunks = Self.realisticChunks(for: steps)
        let naturalTotal = chunks.reduce(0) { $0 + $1.duration + $1.gapAfter }
        let scale = naturalTotal > 0 ? end.timeIntervalSince(start) / naturalTotal : 1

        let batchID = UUID().uuidString
        let metadata = [Self.batchIDKey: batchID]

        var cursor = start
        var samples: [HKQuantitySample] = []

        for chunk in chunks {
            let chunkStart = cursor
            let chunkEnd = chunkStart.addingTimeInterval(chunk.duration * scale)
            cursor = chunkEnd.addingTimeInterval(chunk.gapAfter * scale)

            let distance = Double(chunk.steps) * metersPerStep * Double.random(in: 0.9...1.1)
            let energy = Double(chunk.steps) * kcalPerStep * Double.random(in: 0.9...1.1)

            samples.append(HKQuantitySample(
                type: stepType,
                quantity: HKQuantity(unit: .count(), doubleValue: Double(chunk.steps)),
                start: chunkStart, end: chunkEnd, metadata: metadata
            ))
            samples.append(HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: chunkStart, end: chunkEnd, metadata: metadata
            ))
            samples.append(HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                start: chunkStart, end: chunkEnd, metadata: metadata
            ))
        }

        _ = try await store.save(samples)
    }

    /// Entries written by this app, newest first — samples sharing a batch ID
    /// (one `writeWalk` call) are summed back into a single logical entry.
    func fetchHistory(limit: Int = 30) async throws -> [WalkEntry] {
        async let stepGroups = groupedTotals(for: stepType, unit: .count())
        async let distanceGroups = groupedTotals(for: distanceType, unit: .meter())
        async let energyGroups = groupedTotals(for: energyType, unit: .kilocalorie())
        let (steps, distances, energies) = try await (stepGroups, distanceGroups, energyGroups)

        let entries = steps.map { key, value in
            WalkEntry(
                id: key,
                steps: Int(value.total.rounded()),
                distanceMeters: distances[key]?.total ?? 0,
                kcal: energies[key]?.total ?? 0,
                writtenAt: value.writtenAt,
                batchID: value.fallbackSample == nil ? key : nil,
                fallbackSample: value.fallbackSample
            )
        }
        return Array(entries.sorted { $0.writtenAt > $1.writtenAt }.prefix(limit))
    }

    func delete(_ entry: WalkEntry) async throws {
        guard let batchID = entry.batchID else {
            if let sample = entry.fallbackSample {
                _ = try await store.delete([sample])
            }
            return
        }

        let batchPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: .default()),
            NSPredicate(format: "metadata.%K == %@", Self.batchIDKey, batchID),
        ])

        var objectsToDelete: [HKObject] = []
        for type in sampleTypes {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: batchPredicate)],
                sortDescriptors: []
            )
            objectsToDelete += try await descriptor.result(for: store)
        }

        _ = try await store.delete(objectsToDelete)
    }

    private struct GroupTotal {
        var total: Double = 0
        var writtenAt: Date = .distantPast
        var fallbackSample: HKQuantitySample?
    }

    private func groupedTotals(for type: HKQuantityType, unit: HKUnit) async throws -> [String: GroupTotal] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForObjects(from: .default()))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1000
        )
        let samples = try await descriptor.result(for: store)

        var groups: [String: GroupTotal] = [:]
        for sample in samples {
            let batchID = sample.metadata?[Self.batchIDKey] as? String
            let key = batchID ?? sample.uuid.uuidString
            var group = groups[key] ?? GroupTotal(fallbackSample: batchID == nil ? sample : nil)
            group.total += sample.quantity.doubleValue(for: unit)
            group.writtenAt = max(group.writtenAt, sample.endDate)
            groups[key] = group
        }
        return groups
    }

    private struct Chunk {
        let steps: Int
        let duration: TimeInterval
        let gapAfter: TimeInterval
    }

    private static func realisticChunks(for totalSteps: Int) -> [Chunk] {
        let chunkCount = max(1, min(20, min(totalSteps, max(3, totalSteps / 250))))
        var weights = (0..<chunkCount).map { _ in Double.random(in: 0.6...1.4) }
        let weightSum = weights.reduce(0, +)
        weights = weights.map { $0 / weightSum }

        var stepsPerChunk = weights.map { Int(($0 * Double(totalSteps)).rounded()) }
        stepsPerChunk[stepsPerChunk.count - 1] += totalSteps - stepsPerChunk.reduce(0, +)
        stepsPerChunk = stepsPerChunk.map { max($0, 1) }

        return stepsPerChunk.enumerated().map { index, steps in
            let paceStepsPerMinute = Double.random(in: 95...125)
            let duration = Double(steps) / paceStepsPerMinute * 60
            let gapAfter = index < stepsPerChunk.count - 1 ? Double.random(in: 5...90) : 0
            return Chunk(steps: steps, duration: duration, gapAfter: gapAfter)
        }
    }
}
