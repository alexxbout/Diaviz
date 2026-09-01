//
//  SheetComparerCeSoir.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import SwiftData
import SwiftUI

/// Sheet **« Comparer à ce soir »** — la surface de recherche par similarité
/// du coucher (fusion B2+B3).
///
/// L'utilisateur saisit sa glycémie actuelle (le CGM ayant ~3h de retard,
/// c'est la seule donnée que l'app ne connaît pas) ; le reste du contexte
/// (dose de lente, charge 7 j, sport du jour, IOB) est **pré-rempli depuis le
/// hub**. La recherche remonte les soirs passés dont la glycémie de coucher
/// est dans une **bande réglable** (slider ±10…±30 mg/dL), scindés « fini en
/// hypo / resté stable », sur **60 nuits glissantes toutes doses confondues**
/// (corpus `RechercheCoucher`, distinct de la fenêtre de dose du tableau).
///
/// Le contexte de ce soir est proposé en **critères activables** (chips) :
/// même sport, même type de séance, même charge de la semaine, insuline encore
/// active. Ils se combinent en ET et rétrécissent le corpus.
///
/// Chaque chip porte le **nombre de soirs qui resteraient** si on l'activait :
/// avec ~60 nuits, c'est ce qui rend le filtrage utilisable — on voit le coût
/// d'un critère avant de le poser, et un critère qui viderait la liste est
/// désactivé plutôt que de mener à un écran vide sans coupable identifiable.
/// Pas de score de similarité pondéré : opaque, et il inventerait de la
/// précision sur un historique de cette taille.
///
/// Chaque soir est tappable → `SheetDetailSoiree` (sheet empilée).
/// Des faits, jamais un conseil de glucides ou de dose.
struct SheetComparerCeSoir: View {

    /// Dose de lente courante (affichée dans le contexte de ce soir).
    var doseActuelle: Double = 0
    /// Corpus injecté — pour les previews (court-circuite le hub).
    var corpusApercu: RechercheCoucher.Corpus? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var glycemieTexte = ""
    @State private var bande: Double = 15
    @State private var rechercheLancee = false
    @State private var voirTousStables = false
    @State private var corpus: RechercheCoucher.Corpus?
    @State private var contexteCeSoir: RechercheCoucher.ContexteCeSoir?
    @State private var soirDetail: SoirCoucher?
    /// Critères de contexte activés — combinés en ET avec la bande de glycémie.
    @State private var criteresActifs: Set<CritereCoucher> = []
    @FocusState private var champFocus: Bool

    private var glycemie: Int? { Int(glycemieTexte) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    saisie
                    criteresContexte
                    reglageBande
                    boutonRecherche
                    if rechercheLancee { resultats }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Comparer à ce soir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task { charger() }
        .sheet(item: $soirDetail) { soir in
            SheetDetailSoiree(
                soir: soir,
                nuitB1: nuitB1(pour: soir),
                changementDoseRecent: corpus?.changementDoseRecent
            )
        }
    }

    // MARK: - Chargement (corpus 60 nuits + contexte du soir)

    private func charger() {
        corpus = corpusApercu ?? RechercheCoucher.corpus(contexte: modelContext)
        contexteCeSoir = corpusApercu == nil
            ? RechercheCoucher.contexteCeSoir(contexte: modelContext, doseLente: doseActuelle)
            : RechercheCoucher.ContexteCeSoir(doseLente: doseActuelle, charge: .moderee, sport: nil, iob: nil)
    }

    /// Nuit B1 du corpus correspondant à un soir (fenêtre de coucher, puis
    /// jour calendaire) — même convention que `PageHyposCoucher`.
    private func nuitB1(pour soir: SoirCoucher) -> NightChartData? {
        guard let nuits = corpus?.nuits else { return nil }
        let cal = Calendar.current
        if let parFenetre = nuits.first(where: { nuit in
            let fenetre = nuit.basaleTime.addingTimeInterval(-3 * 3600)...nuit.basaleTime.addingTimeInterval(2 * 3600)
            return fenetre.contains(soir.date)
        }) {
            return parFenetre
        }
        return nuits.first { cal.isDate($0.date, inSameDayAs: soir.date) }
    }

    // MARK: - Saisie glycémie

    private var saisie: some View {
        VStack(spacing: 6) {
            Text("Votre glycémie maintenant")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("—", text: $glycemieTexte)
                .keyboardType(.numberPad)
                .focused($champFocus)
                .multilineTextAlignment(.center)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .onChange(of: glycemieTexte) { rechercheLancee = false }
            Text("mg/dL")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(NiveauCarte.carte.forme)
    }

    // MARK: - Critères de contexte (pré-remplis depuis le hub, activables)

    /// Critères proposables d'après le contexte réel de ce soir.
    private var criteresDisponibles: [CritereCoucher] {
        guard let contexte = contexteCeSoir else { return [] }
        return FiltreCoucher.criteres(
            charge: contexte.charge, sport: contexte.sport, iob: contexte.iob
        )
    }

    private var criteresContexte: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ce soir (connu de l'app)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                // La dose de lente n'est pas un critère : sur 60 nuits toutes
                // doses confondues, filtrer dessus reviendrait à revenir à la
                // fenêtre du tableau. Affichée pour mémoire, pas activable.
                if let dose = contexteCeSoir?.doseLente, dose > 0 {
                    Text("lente \(dose.formatted()) u")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            FlowLayout(spacing: 6) {
                ForEach(criteresDisponibles) { critere in
                    ChipCritereCoucher(
                        critere: critere,
                        actif: criteresActifs.contains(critere),
                        compte: compte(critere),
                        action: { basculer(critere) }
                    )
                }
            }

            Text(criteresActifs.isEmpty
                 ? "Tape un critère pour ne garder que les soirs qui ressemblent à ce soir. Le nombre = soirs restants."
                 : "\(criteresActifs.count) critère\(criteresActifs.count > 1 ? "s" : "") actif\(criteresActifs.count > 1 ? "s" : "") — moins de soirs, donc moins de recul.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Soirs restants si `critere` s'ajoutait aux critères actifs. `nil` tant
    /// qu'aucune glycémie n'est saisie : sans bande, il n'y a pas de base.
    private func compte(_ critere: CritereCoucher) -> Int? {
        guard let g = glycemie else { return nil }
        return FiltreCoucher.compteSiAjoute(
            critere, dans: soirsDansLaBande(de: g), criteres: criteresActifs
        )
    }

    private func basculer(_ critere: CritereCoucher) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if criteresActifs.contains(critere) {
                criteresActifs.remove(critere)
            } else {
                criteresActifs.insert(critere)
            }
        }
    }

    // MARK: - Bande de similarité (slider)

    private var reglageBande: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Soirs à ±\(Int(bande)) mg/dL")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Spacer()
                if rechercheLancee, let g = glycemie {
                    Text("\(max(0, g - Int(bande)))–\(g + Int(bande))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Slider(value: $bande, in: 10...30, step: 5)
                .accessibilityLabel("Bande de similarité, plus ou moins \(Int(bande)) milligrammes par décilitre")
        }
    }

    // MARK: - Bouton recherche

    private var boutonRecherche: some View {
        Button {
            champFocus = false
            withAnimation(.easeInOut(duration: 0.2)) { rechercheLancee = true }
        } label: {
            Text("Lancer la recherche")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(glycemie == nil)
    }

    // MARK: - Résultats

    @ViewBuilder
    private var resultats: some View {
        if let g = glycemie {
            let proches = soirsProches(de: g)

            if proches.isEmpty {
                let avecCriteres = criteresActifs.isEmpty ? "" : " avec ces critères"
                messageInfo("Aucun soir comparable à ±\(Int(bande)) mg/dL\(avecCriteres) sur les \(RechercheCoucher.fenetreNuits) dernières nuits. Pas de quoi conclure.")
            } else {
                let hypos = proches.filter(\.enHypo)
                let stables = proches.filter { !$0.enHypo }

                VStack(alignment: .leading, spacing: 14) {
                    Text("\(proches.count) soir\(proches.count > 1 ? "s" : "") à ±\(Int(bande)) mg/dL de \(g)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if !hypos.isEmpty {
                        groupe(titre: "Fini en hypo", couleur: .red, soirs: hypos)
                    }
                    if !stables.isEmpty {
                        groupeStables(stables)
                    }

                    Text(noteBasDePage)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Base de comparaison : soirs du corpus dans la bande de glycémie, **sans**
    /// les critères de contexte. C'est sur elle que se comptent les chips —
    /// chacune montre alors ce qu'elle retirerait à la sélection courante.
    private func soirsDansLaBande(de g: Int) -> [SoirCoucher] {
        (corpus?.soirs ?? []).filter { abs($0.glycemie - g) <= Int(bande) }
    }

    /// Résultats affichés : bande de glycémie **et** critères actifs, du plus
    /// proche au plus éloigné de la saisie.
    private func soirsProches(de g: Int) -> [SoirCoucher] {
        FiltreCoucher.filtrer(soirsDansLaBande(de: g), par: criteresActifs)
            .sorted { abs($0.glycemie - g) < abs($1.glycemie - g) }
    }

    /// Rappel de portée, adapté à la présence de critères : sans filtre le
    /// contexte affiché sur les lignes reste à comparer à l'œil ; avec filtre
    /// c'est l'effectif réduit qu'il faut garder en tête.
    private var noteBasDePage: String {
        let base = "Recherche sur les \(RechercheCoucher.fenetreNuits) dernières nuits, toutes doses de lente confondues."
        return criteresActifs.isEmpty
            ? base + " Le contexte affiché sur chaque ligne n'est pas filtré — à vous de comparer."
            : base + " Filtrée sur \(criteresActifs.count) critère\(criteresActifs.count > 1 ? "s" : "") : lis les dénominateurs, l'effectif est plus petit."
    }

    // MARK: Groupes de résultats

    private func groupe(titre: String, couleur: Color, soirs: [SoirCoucher]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            enTeteGroupe(titre: titre, n: soirs.count, couleur: couleur)
            VStack(spacing: 8) {
                ForEach(soirs) { soir in
                    LigneSoirCoucher(soir: soir, onTap: { soirDetail = soir })
                }
            }
        }
    }

    /// Groupe « resté stable » — tronqué à 3 soirs pour que les hypos
    /// restent au premier plan ; dépliable.
    private func groupeStables(_ soirs: [SoirCoucher]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            enTeteGroupe(titre: "Resté stable", n: soirs.count, couleur: .green)
            let visibles = voirTousStables ? soirs : Array(soirs.prefix(3))
            VStack(spacing: 8) {
                ForEach(visibles) { soir in
                    LigneSoirCoucher(soir: soir, onTap: { soirDetail = soir })
                }
            }
            if soirs.count > 3 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { voirTousStables.toggle() }
                } label: {
                    Text(voirTousStables
                         ? "Réduire"
                         : "+ \(soirs.count - 3) autres soirs stables")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    }

    private func enTeteGroupe(titre: String, n: Int, couleur: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(couleur)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(titre)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(couleur)
            Text("· \(n)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre) : \(n) soirs")
    }

    private func messageInfo(_ texte: String) -> some View {
        Text(texte)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(NiveauCarte.carte.forme)
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Comparer à ce soir") {
    let fusion = AnalyseHyposCoucher.mock
    return SheetComparerCeSoir(
        doseActuelle: 18,
        corpusApercu: RechercheCoucher.Corpus(
            soirs: fusion.soirs, nuits: [], changementDoseRecent: nil
        )
    )
}
#endif
