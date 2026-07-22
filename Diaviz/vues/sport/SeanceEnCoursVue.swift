//
//  SeanceEnCoursVue.swift
//  diaviz
//

import SwiftUI

/// Écran plein écran d'une séance chronométrée en cours. Chrono central
/// animé, statut (en cours / en pause), boutons Pause·Reprendre / Terminer.
///
/// Le chrono s'anime via une `TimelineView` cadencée à la seconde : le temps
/// affiché est recalculé depuis les horodatages de la `session` (pas de
/// `Timer` à gérer), donc reste juste après un passage en arrière-plan.
///
/// La vue ne détient pas la logique : elle lit `SessionSportService.shared`
/// et déclenche pause/reprise. « Terminer » remonte le brouillon d'activité
/// au parent (qui ouvre la sheet d'enregistrement pré-remplie), « Annuler »
/// abandonne la séance.
struct SeanceEnCoursVue: View {

    let session: SessionSportiveEnCours

    /// Remonte le brouillon (durée chronométrée) pour l'enregistrement.
    var onTerminer: (ActiviteSportive) -> Void
    /// Abandon sans enregistrer.
    var onAnnuler: () -> Void

    @State private var service = SessionSportService.shared
    @State private var afficherConfirmationAnnuler = false

    var body: some View {
        VStack(spacing: 0) {
            barreHaut
            Spacer()
            contenuCentral
            Spacer()
            boutons
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(
            "Abandonner cette séance ?",
            isPresented: $afficherConfirmationAnnuler,
            titleVisibility: .visible
        ) {
            Button("Abandonner", role: .destructive) { onAnnuler() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Le chrono en cours sera perdu, sans enregistrement.")
        }
    }

    // MARK: - Barre du haut (annuler)

    private var barreHaut: some View {
        HStack {
            Button("Annuler") { afficherConfirmationAnnuler = true }
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 20)
    }

    // MARK: - Contenu central

    private var contenuCentral: some View {
        VStack(spacing: 8) {
            badgeStatut
                .padding(.bottom, 20)

            Image(systemName: session.type.icone)
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(session.type.rawValue)
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            chrono

            Text("démarrée à \(heureDebut)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var badgeStatut: some View {
        let enPause = session.enPause
        return HStack(spacing: 6) {
            Circle()
                .fill(enPause ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(enPause ? "En pause" : "En cours")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(enPause ? .orange : .green)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background((enPause ? Color.orange : Color.green).opacity(0.15), in: Capsule())
    }

    /// Chrono central. En cours : `Text(_, style: .timer)` piloté par le
    /// système (fluide, sans redraw manuel). En pause : valeur figée
    /// reformatée à la seconde via `TimelineView`.
    @ViewBuilder
    private var chrono: some View {
        if session.enPause {
            Text(chronoFormate(session.secondesEcoulees()))
                .font(.system(size: 60, weight: .medium, design: .rounded))
                .monospacedDigit()
        } else {
            Text(session.dateReference, style: .timer)
                .font(.system(size: 60, weight: .medium, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Boutons

    private var boutons: some View {
        HStack(spacing: 10) {
            if session.enPause {
                boutonPrincipal(
                    titre: "Reprendre",
                    systemImage: "play.fill",
                    couleur: .green
                ) { service.reprendre() }
            } else {
                boutonPrincipal(
                    titre: "Pause",
                    systemImage: "pause.fill",
                    couleur: Color(.secondarySystemGroupedBackground),
                    teinteTexte: .primary
                ) { service.pause() }
            }

            boutonPrincipal(
                titre: "Terminer",
                systemImage: "stop.fill",
                couleur: Color.red.opacity(0.15),
                teinteTexte: .red
            ) {
                if let brouillon = service.terminer() {
                    onTerminer(brouillon)
                }
            }
        }
    }

    private func boutonPrincipal(
        titre: String,
        systemImage: String,
        couleur: Color,
        teinteTexte: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(titre, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(teinteTexte)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(couleur, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var heureDebut: String {
        Self.formatterHeure.string(from: session.dateDebut)
    }

    private static let formatterHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "H'h'mm"
        return f
    }()

    private func chronoFormate(_ secondes: TimeInterval) -> String {
        let total = Int(secondes)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

#Preview("En cours") {
    SeanceEnCoursVue(
        session: SessionSportiveEnCours(type: .course, dateDebut: Date().addingTimeInterval(-754)),
        onTerminer: { _ in },
        onAnnuler: {}
    )
}

#Preview("En pause") {
    SeanceEnCoursVue(
        session: SessionSportiveEnCours(
            type: .velo,
            dateDebut: Date().addingTimeInterval(-1230),
            secondesPauseCumulees: 0,
            debutPauseCourante: Date().addingTimeInterval(-30)
        ),
        onTerminer: { _ in },
        onAnnuler: {}
    )
}
