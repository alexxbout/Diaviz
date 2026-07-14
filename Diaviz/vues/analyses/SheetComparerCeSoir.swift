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
/// Le contexte n'est **pas** un filtre : il est affiché sur chaque ligne pour
/// comparaison humaine (transparence, pas de score). Le matching de contexte
/// est porté par la **situation épinglée** : si la glycémie saisie + le
/// contexte connu correspondent à une situation minée de la page, sa carte
/// remonte avec le badge « ce soir ».
///
/// Chaque soir est tappable → `SheetDetailSoiree` (sheet empilée).
/// Des faits, jamais un conseil de glucides ou de dose.
struct SheetComparerCeSoir: View {

    /// Situations minées de la page (fenêtre de dose courante) — pour
    /// l'épinglage après saisie.
    var situations: [SituationCoucher] = []
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
    @FocusState private var champFocus: Bool

    private var glycemie: Int? { Int(glycemieTexte) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    saisie
                    recapContexte
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
            Text("Ta glycémie maintenant")
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Récap contexte de ce soir (pré-rempli depuis le hub)

    private var recapContexte: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ce soir (connu de l'app)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                if let contexte = contexteCeSoir {
                    if contexte.doseLente > 0 {
                        ChipContexte(chip: .init(symbole: "syringe.fill",
                                                 texte: "lente \(contexte.doseLente.formatted())u",
                                                 accent: false))
                    }
                    ChipCharge(charge: contexte.charge)
                    if let sport = contexte.sport {
                        ChipContexte(chip: .init(symbole: "figure.run",
                                                 texte: "\(sport.type) · \(sport.dureeTexte)",
                                                 accent: false))
                    }
                    if let iob = contexte.iob {
                        ChipContexte(chip: .init(symbole: "drop.fill",
                                                 texte: "IOB \(String(format: "%.1f", iob))U",
                                                 accent: false))
                    }
                }
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

            if let situation = situationEpinglee(glycemie: g) {
                CarteSituationCoucher(situation: situation, epinglee: true)
            }

            if proches.isEmpty {
                messageInfo("Aucun soir comparable à ±\(Int(bande)) mg/dL sur les \(RechercheCoucher.fenetreNuits) dernières nuits. Pas de quoi conclure.")
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

                    Text("Recherche sur les \(RechercheCoucher.fenetreNuits) dernières nuits, toutes doses de lente confondues. Le contexte affiché n'est pas un filtre — à toi de comparer.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Soirs du corpus dont la glycémie est dans la bande, du plus proche au
    /// plus éloigné de la saisie.
    private func soirsProches(de g: Int) -> [SoirCoucher] {
        (corpus?.soirs ?? [])
            .filter { abs($0.glycemie - g) <= Int(bande) }
            .sorted { abs($0.glycemie - g) < abs($1.glycemie - g) }
    }

    /// Situation minée correspondant au contexte de ce soir : tous ses
    /// facteurs sont présents sur un **pseudo-soir** construit avec la
    /// glycémie saisie + le contexte connu. Les facteurs inconnaissables ce
    /// soir (catégorie B1, correction pas encore prise) ne matchent pas —
    /// honnête par construction.
    private func situationEpinglee(glycemie g: Int) -> SituationCoucher? {
        guard let contexte = contexteCeSoir else { return nil }
        let pseudoSoir = SoirCoucher(
            id: UUID(), date: Date(), glycemie: g, tendance: .stable,
            correction: nil, glucides: nil, sport: contexte.sport,
            iob: contexte.iob, charge: contexte.charge, categorieB1: nil,
            enHypo: false, delaiHypoMinutes: nil, issueCorrection: nil
        )
        return situations.first { situation in
            situation.facteurs.allSatisfy { $0.present(dans: pseudoSoir) }
        }
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
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Comparer à ce soir") {
    let fusion = AnalyseHyposCoucher.mock
    return SheetComparerCeSoir(
        situations: fusion.situations,
        doseActuelle: 18,
        corpusApercu: RechercheCoucher.Corpus(
            soirs: fusion.soirs, nuits: [], changementDoseRecent: nil
        )
    )
}
#endif
