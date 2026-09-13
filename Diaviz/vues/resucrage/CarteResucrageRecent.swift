//
//  CarteResucrageRecent.swift
//  diaviz
//

import SwiftUI

/// Grande carte « dernier resucrage » — chrono depuis la dernière prise.
///
/// Deux emplois :
/// - **Page Resucrage** (`ListeResucrages`) : toujours affichée, pas de
///   fenêtre — c'est la page dédiée au sujet.
/// - **Accueil** : affichée seulement dans la fenêtre réglable depuis le
///   profil (`PreferencesAvancees.fenetreAffichageResucrageAccueilHeures`),
///   voir `estDansLaFenetre(dernier:fenetreHeures:now:)` — au-delà, un
///   resucrage vieux de plusieurs jours n'a plus rien d'actionnable et
///   deviendrait du bruit permanent sur l'accueil.
///
/// **Purement factuelle**, aucun verdict ni seuil : même principe que
/// B2/B3 (hypos au coucher) — le fait est montré, pas interprété.
///
/// Visuel adapté à l'**intention** du dernier resucrage (`IntentionResucrage`
/// porte déjà couleur + icône, utilisées ici telles quelles pour que les 3
/// cas se distinguent d'un coup d'œil, cohérent avec `SheetNouveauResucrage`).
struct CarteResucrageRecent: View {

    /// `nil` : aucun resucrage n'a jamais été enregistré.
    let dernier: ResucrageAffiche?

    var now: Date = .now

    /// Tap sur la carte — sur l'accueil, ouvre la page Resucrage. `nil` sur
    /// la page Resucrage elle-même (pas de redirection vers soi-même).
    var onTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { contenuCarte }
                    .buttonStyle(.plain)
            } else {
                contenuCarte
            }
        }
    }

    private var contenuCarte: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Ligne 1 — icône + titre, même agencement que `CarteLenteRappel`
            // (fond neutre de l'accueil, accent porté par l'icône/le texte,
            // pas par le fond de la carte).
            HStack(spacing: 6) {
                Image(systemName: dernier?.intention.icone ?? "cross.case")
                    .font(.subheadline)
                    .foregroundStyle(couleurAccent)
                    .accessibilityHidden(true)

                Text("Dernier resucrage")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }

            if let dernier {
                Text(libelleChrono(depuis: dernier.date))
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .padding(.top, 2)

                Text(sousTitre(pour: dernier))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Aucun resucrage enregistré")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Surface standard de l'accueil — voir `surfaceCarte()`.
        .surfaceCarte()
        .accessibilityElement(children: .combine)
    }

    private var couleurAccent: Color {
        dernier?.intention.couleur ?? .secondary
    }

    /// « 3h42 », ou « 45min » sous l'heure, « Maintenant » sous la minute —
    /// même palier que `FormatDureeSport`.
    private func libelleChrono(depuis date: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "Maintenant" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let r = minutes % 60
        return r == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", r))"
    }

    private func sousTitre(pour resucrage: ResucrageAffiche) -> String {
        let heure = resucrage.date.formatted(date: .omitted, time: .shortened)
        let jour = Calendar.current.isDateInToday(resucrage.date) ? "aujourd'hui" : resucrage.date.formatted(.dateTime.day().month())
        let quantite = "\(resucrage.glucidesTotal) g"
        return "\(jour.prefix(1).uppercased() + jour.dropFirst()) à \(heure) · \(quantite)"
    }
}

// MARK: - Fenêtre d'affichage accueil

extension CarteResucrageRecent {

    /// Fenêtre par défaut si le profil n'en configure pas — 3h : couvre la
    /// correction d'une hypo et son effet immédiat, sans traîner sur l'accueil
    /// le lendemain.
    static let fenetreAccueilParDefautHeures = 3

    /// `true` si la carte doit apparaître sur l'accueil : un resucrage
    /// existe et sa date est encore dans la fenêtre réglée par l'utilisateur.
    static func estDansLaFenetre(
        dernier: ResucrageAffiche?,
        fenetreHeures: Int,
        now: Date = .now
    ) -> Bool {
        guard let dernier else { return false }
        let limite = TimeInterval(fenetreHeures) * 3600
        return now.timeIntervalSince(dernier.date) <= limite
    }
}

#if DEBUG
private func _resucrage(intention: IntentionResucrage, minutesEcoulees: Int, glucides: Int = 15) -> ResucrageAffiche {
    ResucrageAffiche(
        id: UUID(),
        date: Date().addingTimeInterval(-Double(minutesEcoulees) * 60),
        intention: intention,
        glucidesTotal: glucides,
        nomAlimentUnique: "Jus de fruits",
        nombreAliments: 1,
        glycemieCible: nil
    )
}

#Preview("Correctif hypo — 15min") {
    CarteResucrageRecent(dernier: _resucrage(intention: .correctifHypo, minutesEcoulees: 15))
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Préventif maintien — 3h42") {
    CarteResucrageRecent(dernier: _resucrage(intention: .preventifMaintien, minutesEcoulees: 222, glucides: 20))
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Préventif anti-chute — 45min") {
    CarteResucrageRecent(dernier: _resucrage(intention: .preventifAntiChute, minutesEcoulees: 45, glucides: 10))
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Aucun resucrage") {
    CarteResucrageRecent(dernier: nil)
        .padding()
        .background(Color(.systemGroupedBackground))
}
#endif
