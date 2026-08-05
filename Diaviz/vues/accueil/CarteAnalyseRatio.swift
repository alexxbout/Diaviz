//
//  CarteAnalyseRatio.swift
//  diaviz
//

import SwiftUI

/// Carte accueil — progression du mining R1 (`CalculRatioObserve`) vers son
/// seuil `donneesMinimales`, **par moment** (matin/midi/goûter/dîner) ou par
/// « Tous les repas » en mode ratio unique. Une ligne par groupe configuré :
/// ratio actuel + barre `effectif/donneesMinimales`, verte une fois le seuil
/// atteint.
///
/// Masquée si aucun ratio n'est configuré, ou si tous les groupes configurés
/// ont déjà atteint le seuil — utile tant qu'il reste quelque chose à
/// attendre, s'efface une fois la progression complète (même logique que les
/// autres sections conditionnelles de l'accueil).
struct CarteAnalyseRatio: View {

    @Environment(AnalyseRatioService.self) private var analyseRatioService

    /// Ouvre la sheet de détail « Écart de ratio » quand non-nil.
    var onTap: (() -> Void)? = nil

    private var profil: ProfilUtilisateur { ProfilService.shared.profil }

    private var lignes: [LigneProgressionRatio] {
        let sections = analyseRatioService.analyse.sections
        func effectif(_ section: SectionRepas?) -> Int {
            sections.first { $0.groupe == section }?.effectif ?? 0
        }

        switch profil.modeRatio {
        case .unique:
            guard let ratio = profil.ratioUnique else { return [] }
            return [LigneProgressionRatio(libelle: "Tous les repas", ratio: ratio, effectif: effectif(nil))]

        case .parMoment:
            let m = profil.ratiosParMoment
            var resultat: [LigneProgressionRatio] = []
            if let ratio = m.petitDejeuner {
                resultat.append(.init(libelle: "Petit-déjeuner", ratio: ratio, effectif: effectif(.petitDejeuner)))
            }
            if let ratio = m.dejeuner {
                resultat.append(.init(libelle: "Déjeuner", ratio: ratio, effectif: effectif(.dejeuner)))
            }
            if let ratio = m.gouter {
                resultat.append(.init(libelle: "Goûter", ratio: ratio, effectif: effectif(.enCas)))
            }
            if let ratio = m.diner {
                // Dîner et Nuit partagent le même ratio configuré (voir
                // `InsightsService.ratioConfigure`) mais restent deux groupes
                // de mining distincts (heure réelle du repas) — additionnés
                // ici pour représenter fidèlement toute la donnée qui
                // alimente ce ratio.
                resultat.append(.init(libelle: "Dîner", ratio: ratio, effectif: effectif(.diner) + effectif(.nuit)))
            }
            return resultat
        }
    }

    /// Utile tant qu'au moins un groupe configuré n'a pas atteint le seuil —
    /// une fois tout complet, la carte n'apporte plus rien.
    private var incomplet: Bool {
        lignes.contains { $0.effectif < CalculRatioObserve.donneesMinimales }
    }

    var body: some View {
        if !lignes.isEmpty && incomplet {
            if let onTap {
                Button(action: onTap) { contenu }
                    .buttonStyle(.plain)
            } else {
                contenu
            }
        }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analyse du ratio")
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                ForEach(lignes) { ligne in
                    ligneVue(ligne)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func ligneVue(_ ligne: LigneProgressionRatio) -> some View {
        let complet = ligne.effectif >= CalculRatioObserve.donneesMinimales
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(ligne.libelle) · \(ligne.ratioAffiche)")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Spacer()
                if complet {
                    Text("Prêt")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                } else {
                    Text("\(ligne.effectif) / \(CalculRatioObserve.donneesMinimales)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(complet ? Color.green : Color.accentColor)
                            .frame(width: geo.size.width * ligne.progression)
                    }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ligne.libelle), ratio \(ligne.ratioAffiche), \(ligne.effectif) sur \(CalculRatioObserve.donneesMinimales) repas analysés")
    }
}

/// Une ligne de progression — un groupe (moment ou « Tous les repas »).
private struct LigneProgressionRatio: Identifiable {
    let libelle: String
    let ratio: Double
    let effectif: Int

    var id: String { libelle }

    var ratioAffiche: String { "1u/\(Int(ratio.rounded()))g" }

    var progression: Double {
        min(1, Double(effectif) / Double(CalculRatioObserve.donneesMinimales))
    }
}

// MARK: - Aperçu

#Preview("En cours") {
    CarteAnalyseRatio()
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(AnalyseRatioService())
}
