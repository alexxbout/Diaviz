//
//  SeanceSportiveLiveActivity.swift
//  DiavizSportWidget
//
//  Live Activity + Dynamic Island d'une séance sportive chronométrée.
//  Cible : widget extension `DiavizSportWidget`.
//
//  ⚠️ Ce fichier a besoin du type partagé `ActiviteSportiveAttributes`
//  (défini dans Diaviz/modeles/sport/ActiviteSportiveAttributes.swift) —
//  ajoute ce fichier à la Target Membership du widget dans Xcode.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct SeanceSportiveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActiviteSportiveAttributes.self) { contexte in
            // Bannière écran verrouillé.
            LockScreenSeance(contexte: contexte)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { contexte in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(contexte.attributes.typeLabel)
                            .font(.headline)
                    } icon: {
                        Image(systemName: contexte.attributes.iconeSF)
                            .foregroundStyle(.tint)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    chrono(contexte.state)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(contexte.state.enPause ? "En pause" : "En cours")
                        .font(.caption)
                        .foregroundStyle(contexte.state.enPause ? .orange : .green)
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

    /// Chrono : count-up piloté par le système quand la séance tourne, valeur
    /// figée pendant une pause.
    @ViewBuilder
    private func chrono(_ etat: ActiviteSportiveAttributes.ContentState) -> some View {
        if etat.enPause {
            Text(dureeFormatee(etat.secondesFigees))
        } else {
            Text(etat.dateReference, style: .timer)
                .multilineTextAlignment(.trailing)
        }
    }

    private func dureeFormatee(_ secondes: TimeInterval) -> String {
        let total = Int(secondes)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Bannière écran verrouillé

private struct LockScreenSeance: View {
    let contexte: ActivityViewContext<ActiviteSportiveAttributes>

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contexte.attributes.typeLabel)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(contexte.state.enPause ? "En pause" : "En cours")
                        .font(.caption)
                        .foregroundStyle(contexte.state.enPause ? .orange : .green)
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
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(maxWidth: 130, alignment: .trailing)
        }
        .padding(16)
    }

    private func dureeFormatee(_ secondes: TimeInterval) -> String {
        let total = Int(secondes)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
