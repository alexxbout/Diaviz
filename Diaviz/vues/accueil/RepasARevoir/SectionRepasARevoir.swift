//
//  SectionRepasARevoir.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Carte accueil « Repas à revoir » — **résumé**, pas le détail : un
/// compteur et une répartition par moment de la journée, même patron que
/// `CarteChargeActivite` / `CarteGlucidesSemaine` (icône+titre teintés, gros
/// chiffre+sous-titre, chevron). Le détail complet (graphe, badges,
/// événements) vit désormais uniquement sur `PageTousRepasARevoir`, ouverte
/// au tap — l'accueil n'a plus besoin d'y faire tenir un carrousel de cartes
/// entières.
///
/// La répartition par moment (« 3 petit-déj · 2 dîners ») dit **où** se
/// concentre le problème plutôt que de mettre en avant un seul événement
/// (potentiellement arbitraire) — et annonce le regroupement par moment de
/// la page détail.
///
/// Quand le tableau est vide, affiche un `CartePlaceholderAccueil` au lieu de
/// se masquer — la structure de l'accueil reste la même avant et après le
/// premier repas sorti de cible.
struct SectionRepasARevoir: View {

    let repas: [RepasARevoir]

    /// Ouverture de la liste complète (groupée par moment).
    var onToutVoir: (() -> Void)? = nil

    fileprivate static let teinte = Color.pink

    var body: some View {
        if repas.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Repas à revoir")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)

                // Pas de compteur de progression ici, contrairement aux
                // tendances ou aux glucides : « repas à revoir » n'attend
                // aucun seuil de volume (un seul repas sorti de cible suffit
                // à remonter). Afficher une barre laisserait croire à une
                // collecte en cours qui n'existe pas.
                CartePlaceholderAccueil(
                    icone: "fork.knife",
                    message: "Les repas dont la glycémie est sortie de cible s'afficheront ici."
                )
            }
        } else if let onToutVoir {
            Button(action: onToutVoir) { carte }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre le détail des repas à revoir, groupés par moment")
        } else {
            carte
        }
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: 14) {
            ligneTitre
            ligneContenu
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
        .overlay(NiveauCarte.carte.forme.strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(labelAccessibilite)
    }

    private var ligneTitre: some View {
        HStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinte)
            Text("Repas à revoir")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinte)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    private var ligneContenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(repas.count)")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(repartitionParMoment)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    /// « 3 petit-déj · 2 dîners » — un moment par tranche non vide, dans
    /// l'ordre chronologique de la journée (`SectionRepas.allCases`), jamais
    /// un moment vide affiché à zéro.
    private var repartitionParMoment: String {
        var comptes: [String: Int] = [:]
        for item in repas { comptes[item.libelleSection, default: 0] += 1 }
        let parties = SectionRepas.allCases.compactMap { section -> String? in
            guard let n = comptes[section.titre], n > 0 else { return nil }
            return "\(n) \(libelleCourt(section, pluriel: n > 1))"
        }
        return parties.joined(separator: " · ")
    }

    private func libelleCourt(_ section: SectionRepas, pluriel: Bool) -> String {
        switch section {
        case .petitDejeuner: return "petit-déj"
        case .dejeuner:      return pluriel ? "déjeuners" : "déjeuner"
        case .enCas:         return "en-cas"
        case .diner:         return pluriel ? "dîners" : "dîner"
        case .nuit:          return pluriel ? "nuits" : "nuit"
        }
    }

    private var labelAccessibilite: String {
        "Repas à revoir, \(repas.count). \(repartitionParMoment)"
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Résumé") {
    ScrollView {
        SectionRepasARevoir(repas: [.mockPadThai, .mockPizza, .mockBigMac], onToutVoir: {})
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Vide (placeholder)") {
    ScrollView {
        SectionRepasARevoir(repas: [])
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Sombre") {
    ScrollView {
        SectionRepasARevoir(repas: [.mockPadThai, .mockPizza], onToutVoir: {})
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
#endif
