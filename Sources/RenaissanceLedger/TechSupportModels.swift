import Foundation

enum TechSupportStatus: String, Codable, CaseIterable, Identifiable {
    case queued
    case investigating
    case readyForCodex
    case implementing
    case completed
    case needsHumanReview
    case failed

    var id: String { rawValue }
}

struct TechSupportRequest: Codable, Identifiable, Hashable {
    var id: UUID
    var createdAt: String
    var appVersion: String
    var requestSource: String
    var userMessage: String
    var selectedTab: String
    var visibleWindowTitles: [String]
    var status: TechSupportStatus
}

struct TechSupportCompletionNotice: Codable, Identifiable, Hashable {
    var id: UUID
    var requestID: UUID
    var completedAt: String
    var dadSummaryTitle: String
    var dadSummaryBody: String
    var technicalSummary: String
    var filesChanged: [String]
    var appWasRestarted: Bool
}
