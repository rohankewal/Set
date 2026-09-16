import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A plain-JSON snapshot of everything logged. The store is private to the
/// device, so export is the only way data ever leaves — and it's user-initiated,
/// goes through the share sheet, and contains nothing the user didn't enter.
struct TrainingArchive: Codable, Transferable {
    struct SetEntry: Codable {
        var index: Int
        var weightKg: Double
        var reps: Int
        var seconds: Int
        var isWarmup: Bool
        var completedAt: Date?
    }

    struct Block: Codable {
        var exercise: String
        var muscle: String
        var restSeconds: Int
        var sets: [SetEntry]
    }

    struct Session: Codable {
        var title: String
        var startedAt: Date
        var endedAt: Date?
        var notes: String
        var blocks: [Block]
    }

    struct Record: Codable {
        var kind: String
        var exercise: String
        var value: Double
        var achievedAt: Date
    }

    struct Person: Codable {
        var name: String
        var sessions: [Session]
        var milestones: [Record]
    }

    var exportedAt: Date = .now
    var schemaVersion = 1
    var athletes: [Person]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { archive in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(archive)
        }
        .suggestedFileName { _ in
            "set-export-\(Date.now.formatted(.iso8601.year().month().day())).json"
        }
    }

    @MainActor
    static func build(from context: ModelContext) -> TrainingArchive {
        let athletes = (try? context.fetch(FetchDescriptor<Athlete>())) ?? []
        return TrainingArchive(
            athletes: athletes.map { athlete in
                Person(
                    name: athlete.name,
                    sessions: athlete.completedSessions.map { session in
                        Session(
                            title: session.title,
                            startedAt: session.startedAt,
                            endedAt: session.endedAt,
                            notes: session.notes,
                            blocks: session.orderedBlocks.map { block in
                                Block(
                                    exercise: block.name,
                                    muscle: block.exercise?.muscle.rawValue ?? "",
                                    restSeconds: block.restSeconds,
                                    sets: block.orderedSets.map { set in
                                        SetEntry(
                                            index: set.index,
                                            weightKg: set.weightKg,
                                            reps: set.reps,
                                            seconds: set.seconds,
                                            isWarmup: set.isWarmup,
                                            completedAt: set.completedAt
                                        )
                                    }
                                )
                            }
                        )
                    },
                    milestones: athlete.allMilestones
                        .filter { $0.previousValue > 0 || !$0.kind.isExerciseScoped }
                        .map {
                            Record(
                                kind: $0.kind.rawValue,
                                exercise: $0.exerciseName,
                                value: $0.value,
                                achievedAt: $0.achievedAt
                            )
                        }
                )
            }
        )
    }
}

/// The same log as a spreadsheet. One row per set, which is the shape every
/// other tracker exports and every analysis tool expects.
struct TrainingCSV: Transferable {
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { csv in
            Data(csv.text.utf8)
        }
        .suggestedFileName { _ in
            "set-export-\(Date.now.formatted(.iso8601.year().month().day())).csv"
        }
    }

    @MainActor
    static func build(from context: ModelContext, unit: WeightUnit) -> TrainingCSV {
        let athletes = (try? context.fetch(FetchDescriptor<Athlete>())) ?? []
        var lines = [
            "date,athlete,workout,exercise,muscle,set,type,weight_\(unit.short),reps,seconds,rpe,volume_\(unit.short)"
        ]

        func escape(_ value: String) -> String {
            value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                : value
        }

        for athlete in athletes {
            for session in athlete.completedSessions.sorted(by: { $0.startedAt < $1.startedAt }) {
                for block in session.orderedBlocks {
                    for set in block.orderedSets where set.isComplete {
                        let fields: [String] = [
                            (set.completedAt ?? session.startedAt).formatted(.iso8601),
                            escape(athlete.name),
                            escape(session.title),
                            escape(block.name),
                            block.exercise?.muscle.rawValue ?? "",
                            "\(set.index + 1)",
                            set.kind.rawValue,
                            Format.number(unit.fromKilograms(set.weightKg)),
                            "\(set.reps)",
                            "\(set.seconds)",
                            set.rpe.map { Format.number($0) } ?? "",
                            Format.number(unit.fromKilograms(set.volumeKg))
                        ]
                        lines.append(fields.joined(separator: ","))
                    }
                }
            }
        }

        return TrainingCSV(text: lines.joined(separator: "\n"))
    }
}
