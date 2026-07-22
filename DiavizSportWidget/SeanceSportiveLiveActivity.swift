//
//  SeanceSportiveLiveActivity.swift
//  DiavizSportWidget
//
//  Live Activity + Dynamic Island d'une séance sportive chronométrée.
//  Cible : widget extension `DiavizSportWidget`.
//
//  ⚠️ A besoin des types partagés (Target Membership sur les deux cibles) :
//  ActiviteSportiveAttributes, et les intents des boutons
//  (BasculerPauseSeanceIntent / TerminerSeanceIntent).
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct SeanceSportiveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActiviteSportiveAttributes.self) { contexte in
            LockScreenSeance(contexte: contexte)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { contexte in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: contexte.attributes.iconeSF)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        chrono(contexte.state)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("démarré à \(heure(contexte.attributes.dateDebut))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(contexte.attributes.typeLabel)
                                .font(.title.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .foregroundStyle(.white)
                            Spacer(minLength: 8)
                            badgeStatut(contexte.state)
                        }
                        HStack(spacing: 10) {
                            boutonPause(contexte.state)
                            boutonTerminer()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: contexte.attributes.iconeSF)
                    .foregroundStyle(.tint)
            } compactTrailing: {
                chrono(contexte.state)
                    .monospacedDigit()
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: contexte.attributes.iconeSF)
                    .foregroundStyle(.tint)
            }
            .keylineTint(.blue)
        }
    }

    // MARK: - Boutons interactifs

    /// Badge de statut mis en avant (capsule teintée).
    private func badgeStatut(_ etat: ActiviteSportiveAttributes.ContentState) -> some View {
        let enPause = etat.enPause
        return Text(statut(etat))
            .font(.caption.weight(.bold))
            .foregroundStyle(enPause ? .orange : .green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((enPause ? Color.orange : Color.green).opacity(0.22), in: Capsule())
    }

    private func boutonPause(_ etat: ActiviteSportiveAttributes.ContentState) -> some View {
        Button(intent: BasculerPauseSeanceIntent()) {
            Label(etat.enPause ? "Reprendre" : "Pause",
                  systemImage: etat.enPause ? "play.fill" : "pause.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .contentTransition(.identity)
        }
        .tint(etat.enPause ? .green : .gray)
        .transaction { $0.animation = nil }
    }

    private func boutonTerminer() -> some View {
        Button(intent: TerminerSeanceIntent()) {
            Label("Terminer", systemImage: "stop.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .tint(.red)
    }

    // MARK: - Chrono

    @ViewBuilder
    private func chrono(_ etat: ActiviteSportiveAttributes.ContentState) -> some View {
        if etat.enPause {
            Text(dureeFormatee(etat.secondesFigees))
        } else {
            Text(etat.dateReference, style: .timer)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Bannière écran verrouillé

private struct LockScreenSeance: View {
    let contexte: ActivityViewContext<ActiviteSportiveAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contexte.attributes.typeLabel)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(statut(contexte.state)) · démarré à \(heure(contexte.attributes.dateDebut))")
                            .font(.caption)
                            .foregroundStyle(contexte.state.enPause ? .orange : .secondary)
                    }
                } icon: {
                    Image(systemName: contexte.attributes.iconeSF)
                        .font(.title2)
                        .foregroundStyle(.tint)
                }

                Spacer()

                Group {
                    if contexte.state.enPause {
                        Text(dureeFormatee(contexte.state.secondesFigees))
                    } else {
                        Text(contexte.state.dateReference, style: .timer)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: 120, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Button(intent: BasculerPauseSeanceIntent()) {
                    Label(contexte.state.enPause ? "Reprendre" : "Pause",
                          systemImage: contexte.state.enPause ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(contexte.state.enPause ? .green : .gray)
                Button(intent: TerminerSeanceIntent()) {
                    Label("Terminer", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

// MARK: - Helpers partagés (fichier)

private func statut(_ etat: ActiviteSportiveAttributes.ContentState) -> String {
    etat.enPause ? "En pause" : "En cours"
}

private func heure(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%dh%02d", c.hour ?? 0, c.minute ?? 0)
}

private func dureeFormatee(_ secondes: TimeInterval) -> String {
    let total = Int(secondes)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}
