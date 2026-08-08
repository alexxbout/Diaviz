//
//  CarteAnalyseRatio.swift
//  diaviz
//

import SwiftUI

/// Carte accueil — progression du mining R1 (`CalculRatioObserve`) vers son
/// seuil `donneesMinimales`, **par moment** (matin/midi/goûter/dîner) ou par
/// « Tous les repas » en mode ratio unique. Une ligne par groupe : libellé,
/// barre de progression, effectif — toutes les barres sur la même échelle
/// (0 → `donneesMinimales`), donc directement comparables entre moments.
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Analyse des ratios")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                // Signale que la carte est tappable — sans ça rien n'indique
                // qu'elle ouvre la sheet de détail.
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(spacing: 10) {
                ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                    ligneVue(ligne, index: index)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(labelAccessibilite)
    }

    /// Une ligne par groupe : libellé, barre de progression propre au groupe,
    /// effectif. Chaque barre partage la même échelle (0 → `donneesMinimales`),
    /// donc deux moments se comparent directement à l'œil — contrairement à une
    /// barre empilée globale où un groupe déjà prêt n'occupe qu'une fraction de
    /// la largeur.
    ///
    /// Colonnes latérales à largeur fixe pour que les libellés et les chiffres
    /// s'alignent verticalement quelle que soit la longueur du texte.
    @ViewBuilder
    private func ligneVue(_ ligne: LigneProgressionRatio, index: Int) -> some View {
        let teinte = couleur(index: index, complet: ligne.estComplet)
        HStack(spacing: 10) {
            Text(ligne.libelleCourt)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 74, alignment: .leading)

            GeometryReader { geo in
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(teinte)
                            .frame(width: geo.size.width * ligne.progression)
                    }
            }
            .frame(height: 8)

            Text(ligne.estComplet ? "Prêt" : "\(ligne.effectif)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ligne.estComplet ? Color.green : .primary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 44, alignment: .trailing)
        }
    }

    /// Une teinte par position dans la journée — vert dès que le groupe a
    /// atteint son seuil, pour que « prêt » se lise sur la barre comme sur le
    /// chiffre, sans dépendre de la couleur d'index.
    private func couleur(index: Int, complet: Bool) -> Color {
        if complet { return .green }
        let palette: [Color] = [.blue, .teal, .orange, .purple]
        return palette[index % palette.count]
    }

    private var labelAccessibilite: String {
        let details = lignes.map { ligne in
            ligne.estComplet
                ? "\(ligne.libelle), ratio \(ligne.ratioAffiche), prêt"
                : "\(ligne.libelle), ratio \(ligne.ratioAffiche), \(ligne.effectif) sur \(CalculRatioObserve.donneesMinimales) repas analysés"
        }
        return (["Analyse des ratios"] + details).joined(separator: ". ")
    }
}

/// Une ligne de progression — un groupe (moment ou « Tous les repas »).
private struct LigneProgressionRatio: Identifiable {
    let libelle: String
    let ratio: Double
    let effectif: Int

    var id: String { libelle }

    var ratioAffiche: String { "1u/\(Int(ratio.rounded()))g" }

    /// Libellé raccourci pour la légende, qui n'a que ~110pt de large à côté
    /// des anneaux — « Petit-déjeuner » y déborderait.
    var libelleCourt: String {
        libelle == "Petit-déjeuner" ? "Petit-déj" : libelle
    }

    var estComplet: Bool { effectif >= CalculRatioObserve.donneesMinimales }

    var progression: Double {
        min(1, Double(effectif) / Double(CalculRatioObserve.donneesMinimales))
    }
}

// MARK: - Aperçu

#if DEBUG
/// Service peuplé pour les previews — mêmes repas synthétiques que la preview
/// « App complète » d'`AppTabVues`, dont les ratios (8/12/15) sont alignés sur
/// le profil posé ici. `ProfilService.shared` est isolé du vrai profil de
/// l'iPhone dans le process de preview.
@MainActor
private func _serviceApercu() -> AnalyseRatioService {
    ProfilService.shared.mettreAJour {
        $0 = ProfilUtilisateur(
            prenom: "Camille",
            poidsKg: 78,
            insulineRapide: .fiasp,
            insulineLente: .tresiba,
            dureeActionInsulineHeures: 3.5,
            modeRatio: .parMoment,
            ratioUnique: nil,
            ratiosParMoment: RatiosParMoment(petitDejeuner: 8, dejeuner: 12, gouter: 15, diner: 10),
            ratioCorrection: 35,
            horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(),
            preferencesAvancees: PreferencesAvancees()
        )
    }
    let service = AnalyseRatioService()
    service.recalculer(depuis: RepasService.echantillonsApercuR1())
    return service
}

#Preview("Progression mixte") {
    CarteAnalyseRatio(onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(_serviceApercu())
}

#Preview("Sombre") {
    CarteAnalyseRatio(onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(_serviceApercu())
        .preferredColorScheme(.dark)
}
#endif
