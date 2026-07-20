//
//  PageHyposCoucher.swift
//  diaviz
//

import SwiftUI

/// Section **« Hypos au coucher »** de la page « Analyse du coucher » —
/// fusion des analyses B2 (endormissement) et B3 (corrections du soir),
/// **focus hypo** (l'événement dangereux ; l'issue « insuffisant » de B3
/// reste visible au détail mais ne pilote pas la page).
///
/// Structure purement rétrospective :
///   1. Chiffre honnête (hypos / soirs, fenêtre de dose)
///   2. Situations observées (combinaisons minées, avec contraste + dénominateurs)
///   3. Soirs en hypo (liste), stables en compteur, « Voir tout »
///   4. Bouton « Comparer à ce soir » → sheet de recherche (saisie glycémie)
///
/// Le « ce soir » vit entièrement dans la sheet : la glycémie CGM arrive avec
/// ~3h de retard, aucune détection automatique de situation n'est possible ici.
struct PageHyposCoucher: View {

    let analyse: AnalyseHyposCoucher
    /// Nuits B1 (courbes, zones, events) — alimentent la sheet détail de
    /// soirée. Vide en preview → sheet en dégradation gracieuse.
    var nuitsB1: [NightChartData] = []

    /// Filtre de la liste des soirs. Défaut « hypos » quand il y en a, sinon
    /// « tous » (une liste vide sous un filtre sélectionné serait déroutante).
    enum FiltreSoirs { case hypos, tous }
    @State private var filtre: FiltreSoirs = .hypos

    /// Tri de la liste — date (plus récent d'abord, défaut) ou glycémie
    /// (croissante).
    enum TriSoirs { case date, glycemie }
    @State private var tri: TriSoirs = .date

    @State private var afficherComparer = false
    @State private var soirSelectionne: SoirCoucher?

    /// Filtre effectif : bascule sur « tous » s'il n'y a aucune hypo à montrer.
    private var filtreEffectif: FiltreSoirs {
        analyse.totalHypos == 0 ? .tous : filtre
    }

    var body: some View {
        VStack(spacing: 12) {
            enTeteChiffre
            if !analyse.situations.isEmpty {
                sectionSituations
            }
            sectionSoirs
            boutonComparer
        }
        .sheet(isPresented: $afficherComparer) {
            SheetComparerCeSoir(situations: analyse.situations, doseActuelle: analyse.doseActuelle)
        }
        .sheet(item: $soirSelectionne) { soir in
            SheetDetailSoiree(
                soir: soir,
                nuitB1: nuitB1(pour: soir),
                changementDoseRecent: analyse.changementDoseRecent
            )
        }
    }

    /// Nuit B1 correspondant à un soir : d'abord par contenance dans la
    /// fenêtre de coucher (robuste aux corrections après minuit), sinon par
    /// jour calendaire.
    private func nuitB1(pour soir: SoirCoucher) -> NightChartData? {
        let cal = Calendar.current
        if let parFenetre = nuitsB1.first(where: { nuit in
            let fenetre = nuit.basaleTime.addingTimeInterval(-3 * 3600)...nuit.basaleTime.addingTimeInterval(2 * 3600)
            return fenetre.contains(soir.date)
        }) {
            return parFenetre
        }
        return nuitsB1.first { cal.isDate($0.date, inSameDayAs: soir.date) }
    }

    // MARK: - 1. Chiffre honnête

    private var enTeteChiffre: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(analyse.totalHypos)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(analyse.totalHypos > 0 ? .red : .green)

            VStack(alignment: .leading, spacing: 2) {
                Text("hypo\(analyse.totalHypos > 1 ? "s" : "") sur \(analyse.totalSoirs) soir\(analyse.totalSoirs > 1 ? "s" : "") analysé\(analyse.totalSoirs > 1 ? "s" : "")")
                    .font(.subheadline.weight(.medium))
                if let date = analyse.changementDoseRecent {
                    Text("depuis le changement de dose du \(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("lente actuelle : \(analyse.doseActuelle.formatted()) u")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 2. Situations observées

    private var sectionSituations: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Situations observées")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("triées par écart")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(analyse.situations) { situation in
                CarteSituationCoucher(situation: situation)
            }

            Text("Co-occurrences observées, pas des causes confirmées. Seules les situations avec assez de soirs et un écart net apparaissent ici.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 3. Soirs (filtre segmenté hypos / tous)

    private var soirsVisibles: [SoirCoucher] {
        let base: [SoirCoucher]
        switch filtreEffectif {
        case .hypos: base = analyse.soirsEnHypo
        case .tous:  base = analyse.soirs
        }
        switch tri {
        case .date:     return base.sorted { $0.date > $1.date }
        case .glycemie: return base.sorted { $0.glycemie < $1.glycemie }
        }
    }

    private var sectionSoirs: some View {
        VStack(alignment: .leading, spacing: 10) {
            enTeteSoirs

            let visibles = soirsVisibles
            if visibles.isEmpty {
                Text(messageVide)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(visibles) { soir in
                        LigneSoirCoucher(soir: soir, onTap: { soirSelectionne = soir })
                    }
                }
            }
        }
    }

    /// Titre + filtre segmenté « Hypos · N / Tous · M » + tri (glycémie /
    /// date), tout à droite sur la même ligne.
    private var enTeteSoirs: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Soirs analysés")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if analyse.totalHypos > 0 {
                segmentFiltre
            }
            menuTri
        }
    }

    /// Menu de tri compact (icône seule) — « Glycémie » (croissante) ou
    /// « Date » (plus récent d'abord, défaut).
    private var menuTri: some View {
        Menu {
            Picker("Trier par", selection: $tri) {
                Label("Date", systemImage: "calendar").tag(TriSoirs.date)
                Label("Glycémie", systemImage: "drop").tag(TriSoirs.glycemie)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(6)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .accessibilityLabel("Trier les soirs")
        .accessibilityValue(tri == .date ? "Par date" : "Par glycémie")
    }

    private var segmentFiltre: some View {
        HStack(spacing: 2) {
            segment(.hypos, libelle: "Hypos", compte: analyse.totalHypos, teinte: .red)
            segment(.tous, libelle: "Tous", compte: analyse.totalSoirs, teinte: .secondary)
        }
        .padding(2)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func segment(_ valeur: FiltreSoirs, libelle: String, compte: Int, teinte: Color) -> some View {
        let actif = filtreEffectif == valeur
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { filtre = valeur }
        } label: {
            Text("\(libelle) · \(compte)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(actif ? teinte : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background {
                    if actif {
                        Capsule().fill(Color(.secondarySystemGroupedBackground))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
    }

    private var messageVide: String {
        analyse.totalSoirs == 0
            ? "Aucun soir analysable pour l'instant — il faut des nuits avec lente et couverture CGM."
            : "Aucune hypo sur \(analyse.totalSoirs) soir\(analyse.totalSoirs > 1 ? "s" : "") analysé\(analyse.totalSoirs > 1 ? "s" : "")."
    }

    // MARK: - 4. Comparer à ce soir

    private var boutonComparer: some View {
        Button {
            afficherComparer = true
        } label: {
            Label("Comparer ma glycémie de ce soir", systemImage: "magnifyingglass")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

// MARK: - Carte d'une situation

/// Une situation minée : titre (facteurs), barre « cette situation » vs barre
/// de contraste, dénominateurs bruts. Le pourcentage n'est jamais affiché
/// seul — la longueur de barre le porte, les chiffres restent des effectifs.
struct CarteSituationCoucher: View {

    let situation: SituationCoucher
    /// `true` → carte épinglée « ce soir » (bordure accent + badge) : le
    /// contexte du moment correspond à cette situation (sheet Comparer).
    var epinglee: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                titreSituation
                    .font(.footnote.weight(.semibold))
                if situation.estFacteurSeul && !epinglee {
                    Text("facteur seul")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if epinglee {
                    Text("ce soir")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.14), in: Capsule())
                }
            }

            barre(libelle: "cette situation",
                  hypos: situation.hypos, total: situation.total,
                  couleur: .red, accent: true)
            barre(libelle: situation.libelleComplement,
                  hypos: situation.complementHypos, total: situation.complementTotal,
                  couleur: .green, accent: false)

            if situation.fragile {
                Label("\(situation.total) soirs seulement — encore fragile", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay {
            if epinglee {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.55), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible)
    }

    /// Titre composé des facteurs, chacun préfixé de son SF Symbol, joints
    /// par « · » — remplace l'ancien libellé à base d'emoji tout en gardant
    /// un rendu inline dans un seul `Text`.
    private var titreSituation: Text {
        let morceaux = situation.facteurs.map { facteur in
            Text(Image(systemName: facteur.icone)) + Text(" \(facteur.libelle)")
        }
        guard var texte = morceaux.first else { return Text("") }
        for morceau in morceaux.dropFirst() {
            texte = texte + Text(" · ") + morceau
        }
        return texte
    }

    private func barre(libelle: String, hypos: Int, total: Int, couleur: Color, accent: Bool) -> some View {
        HStack(spacing: 8) {
            Text(libelle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
                .lineLimit(2)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(couleur.opacity(accent ? 0.85 : 0.5))
                        .frame(width: max(3, geo.size.width * fraction(hypos, total)))
                }
            }
            .frame(height: 7)

            Text("\(hypos) / \(total)")
                .font(.caption.weight(accent ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(accent ? couleur : .secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func fraction(_ hypos: Int, _ total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(hypos) / CGFloat(total)
    }

    private var libelleAccessible: String {
        "\(situation.titre) : \(situation.hypos) hypos sur \(situation.total) soirs. "
            + "\(situation.libelleComplement) : \(situation.complementHypos) sur \(situation.complementTotal)."
            + (situation.fragile ? " Effectif faible, à lire avec prudence." : "")
    }
}

// MARK: - Aperçus

#Preview("Hypos au coucher — mock") {
    ScrollView {
        PageHyposCoucher(analyse: .mock)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Hypos au coucher — sans hypo") {
    ScrollView {
        PageHyposCoucher(
            analyse: CalculSituationsCoucher.analyser(
                endormissement: .mockSansHypo, corrections: AnalyseCorrections(corrections: []), timeline: []
            )
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Hypos au coucher — situations riches (avec B1)") {
    ScrollView {
        PageHyposCoucher(analyse: .mockRiche)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Hypos au coucher — seulement corrections (pas de B2)") {
    ScrollView {
        PageHyposCoucher(
            analyse: CalculSituationsCoucher.analyser(
                endormissement: AnalyseEndormissement(seuilCoucher: 160, doseActuelle: 18, nuits: []),
                corrections: .mock, timeline: []
            )
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
