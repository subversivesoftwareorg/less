import Foundation
import Observation
import GRDB

enum InsightFilter: String, CaseIterable {
    case pending
    case reviewed
    case dismissed
    case all

    var label: String {
        switch self {
        case .pending: "Pending"
        case .reviewed: "Reviewed"
        case .dismissed: "Dismissed"
        case .all: "All"
        }
    }

    var matchesStatus: ReviewStatus? {
        switch self {
        case .pending: .pending
        case .reviewed: .reviewed
        case .dismissed: .dismissed
        case .all: nil
        }
    }
}

enum InsightSort: String, CaseIterable {
    case priority
    case newest
    case type

    var label: String {
        switch self {
        case .priority: "Priority"
        case .newest: "Newest"
        case .type: "Type"
        }
    }
}

@Observable final class InsightsViewModel {
    var insights: [Insight] = []
    var reviewRecords: [Int64: ReviewRecord] = [:]
    var isAnalyzing = false
    var errorMessage: String?
    var lastRunDate: Date?
    var filter: InsightFilter = .pending
    var sortOrder: InsightSort = .priority

    private let database: AppDatabase
    private let engine: InsightEngine
    private var observationTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        self.engine = InsightEngine(database: database)
        loadData()
    }

    func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let observation = ValueObservation.tracking { db -> ([Insight], [ReviewRecord]) in
                let insights = try Insight.order(Column("createdAt").desc).fetchAll(db)
                let reviews = try ReviewRecord.fetchAll(db)
                return (insights, reviews)
            }
            do {
                for try await (insights, reviews) in observation.values(in: database.dbQueue) {
                    self.insights = insights
                    self.reviewRecords = Dictionary(
                        uniqueKeysWithValues: reviews.map { ($0.insightId, $0) }
                    )
                }
            } catch {
                dlog("Insights observation error: \(error)", category: "InsightsViewModel")
            }
        }
    }

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
    }

    var filteredInsights: [Insight] {
        var result: [Insight]
        if let status = filter.matchesStatus {
            result = insights.filter { insight in
                let reviewStatus = reviewRecords[insight.id!]?.status ?? .pending
                return reviewStatus == status
            }
        } else {
            result = insights
        }

        switch sortOrder {
        case .priority:
            result.sort { a, b in
                let aPri = a.priorityScore
                let bPri = b.priorityScore
                if aPri != bPri { return aPri > bPri }
                return a.createdAt > b.createdAt
            }
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .type:
            result.sort {
                if $0.type.rawValue != $1.type.rawValue { return $0.type.rawValue < $1.type.rawValue }
                return $0.createdAt > $1.createdAt
            }
        }

        return result
    }

    var pendingCount: Int {
        insights.filter { insight in
            reviewRecords[insight.id!]?.status == .pending
        }.count
    }

    func runAnalysis() {
        isAnalyzing = true
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let run = try await self.engine.runAnalysis()
                self.lastRunDate = run.runDate
                self.loadData()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isAnalyzing = false
        }
    }

    func updateStatus(_ insightId: Int64, status: ReviewStatus, note: String = "") {
        do {
            try database.updateReviewStatus(insightId, status: status, note: note)
        } catch {
            dlog("Failed to update review status: \(error)", category: "InsightsViewModel")
        }
    }

    func reviewStatus(for insightId: Int64) -> ReviewStatus {
        reviewRecords[insightId]?.status ?? .pending
    }

    private func loadData() {
        insights = (try? database.allInsights()) ?? []
        let reviews = insights.compactMap { insight -> (Int64, ReviewRecord)? in
            guard let id = insight.id,
                  let review = try? database.reviewRecord(forInsight: id) else { return nil }
            return (id, review)
        }
        reviewRecords = Dictionary(uniqueKeysWithValues: reviews)
        lastRunDate = (try? database.latestAnalysisRun())?.runDate
    }
}
