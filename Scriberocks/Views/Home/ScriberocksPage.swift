import SwiftUI

/// Scriberocks' own page (the bottom-left button): what it's for, what's
/// new, and ways to pass it on.
struct ScriberocksPage: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image("rock")
                            .font(.system(size: 56))
                            .accessibilityHidden(true)
                        Text("Scriberocks").font(.largeTitle.bold())
                        Text("Write a rock. Swipe through better versions of it.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section("Why Scriberocks") {
                    ForEach(Self.advantages, id: \.title) { item in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.headline)
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: item.symbol).foregroundStyle(.tint)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    ForEach(Array(Self.pipeline.enumerated()), id: \.offset) { i, stage in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(stage.optional ? "+" : "\(i + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.tint)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.title).font(.headline)
                                Text(stage.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("How it works")
                } footer: {
                    Text("ScribeSLM is the language pipeline inside Scriberocks. All of it runs on your iPhone.")
                }

                Section("What's new") {
                    ForEach(Self.announcements, id: \.title) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(note.title).font(.headline)
                                Spacer()
                                Text(note.date, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(note.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    ShareLink(item: Self.appLink, subject: Text("Scriberocks"), message: Text("Write a rock, swipe through better versions of it.")) {
                        Label("Share Scriberocks", systemImage: "square.and.arrow.up")
                    }
                    Link(destination: Self.reviewLink) {
                        Label("Rate on the App Store", systemImage: "star")
                    }
                }
            }
            .navigationTitle("Scriberocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// scribe.rocks/app: a link preview in Messages; iPhones open the App Store.
    static let appLink = URL(string: "https://scribe.rocks/app")!
    static let reviewLink = URL(string: "https://apps.apple.com/app/id6448929626?action=write-review")!

    struct Advantage { let symbol, title, detail: String }
    static let advantages: [Advantage] = [
        Advantage(symbol: "iphone", title: "Runs on your iPhone",
                  detail: "Suggestions are made on the phone. Your writing isn't sent anywhere to get them."),
        Advantage(symbol: "infinity", title: "Buy once, yours forever",
                  detail: "No subscription."),
        Advantage(symbol: "textformat", title: "Your prose style",
                  detail: "Casual for everyday writing, publishable for published prose. Choose in Profile."),
        Advantage(symbol: "clock.arrow.circlepath", title: "Every version kept",
                  detail: "Pull through a rock's history, and branch from any older version."),
    ]

    /// ScribeSLM's four stages, then ScribeIE (Intent-conditioned Editing), the optional fifth.
    struct Stage { let title, detail: String; var optional = false }
    static let pipeline: [Stage] = [
        Stage(title: "Standards, not volume",
              detail: "Its models learned from dictionaries, hand-annotated text and learners' writing, not text scraped in bulk. Every source is open and credited."),
        Stage(title: "Dictionary and usage",
              detail: "Your rock is split into sentences, and each word is tagged and parsed, using a dictionary and a model of how words are actually used."),
        Stage(title: "Dual meanings and synonyms",
              detail: "Words with more than one meaning get the meaning they have in your sentence, and only that meaning's synonyms are considered."),
        Stage(title: "Proposing and judging",
              detail: "Trims, cuts, joins, reorders and word swaps are proposed, then judged by the model for your prose style. Only the ones that fit are shown."),
        Stage(title: "ScribeIE: Generate",
              detail: "Optional, for casual writing. It puts first the suggestions editors would make, and writes its own version of each, underlined in red. Learned from 400,000 edits by Simple English Wikipedia's editors; the casual model checks every word it writes, and it never removes a negation, number or name.",
              optional: true),
    ]

    struct Announcement { let title: String; let date: Date; let detail: String }
    static let announcements: [Announcement] = [
        Announcement(title: "Generate", date: day(2026, 10, 24),
                     detail: "ScribeIE is here for casual writing: turn on Generate in Profile › Writing. Suggestions are ordered by what editors would do, and each gets a version written by ScribeIE, underlined in red."),
        Announcement(title: "Long rocks", date: day(2026, 10, 23),
                     detail: "Write as much as you like and scroll. Suggestions cover the sentences in the highlighted box at the top."),
        Announcement(title: "Casual and publishable", date: day(2026, 10, 23),
                     detail: "Two prose styles, and a variety slider from safer to bolder swaps, in Profile › Writing."),
    ]

    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))!
    }
}

#Preview {
    ScriberocksPage()
}
