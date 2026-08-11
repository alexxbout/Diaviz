//
//  SheetEcartRatio.swift
//  diaviz
//

import SwiftUI

/// Sheet de détail du ratio observé par R1 — ouverte depuis la carte
/// d'insight « Nouvelles tendances » (tap sur l'insight R1 uniquement) et
/// depuis `CarteAnalyseRatio` sur l'accueil. Un bloc par groupe ayant au moins
/// un repas exploitable (filtré par l'appelant) — transparence complète : un
/// groupe bien calibré, ou encore peu fourni, est montré au même titre qu'un
/// groupe en écart. Chaque bloc porte son `GraphiqueZonesRatio` et la légende
/// chiffrée des 3 tranches, les tranches sous `effectifMinimalBucket` étant
/// marquées « insuffisant » plutôt que masquées.
struct SheetEcartRatio: View {

    let sections: [ObservationRatioSection]
    /// Comparaison dose/verdict avant-après le dernier changement de ratio,
    /// par section — absente pour une section jamais modifiée (badge et bloc
    /// masqués, section inchangée). Défaut vide pour ne pas casser les
    /// appelants existants.
    var apercusChangementRatio: [SectionRepas?: ApercuChangementRatio] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sections.isEmpty {
                    ContentUnavailableView(
                        "Pas encore de résultat",
                        systemImage: "chart.dots.scatter",
                        description: Text("Aucun moment n'a encore assez de repas analysés pour être comparé.")
                    )
                } else {
                    Form {
                        Section("Constat") {
                            Label("Un point = un repas, placé selon la dose donnée vs celle de ton ratio (zone grisée).", systemImage: "chart.dots.scatter")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Label("Vert en cible, orange pic modéré, rouge pic élevé ou hypo.", systemImage: "circle.fill")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Label("Un côté qui bat le milieu = ratio trop fort à gauche, trop faible à droite.", systemImage: "arrow.left.arrow.right")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(sections, id: \.groupe) { section in
                            Section {
                                if let apercu = apercusChangementRatio[section.groupe] {
                                    blocDepuisChangement(apercu)
                                }

                                GraphiqueZonesRatio(entrees: section.entrees)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                                // Une légende à 3 colonnes n'a de sens que si au
                                // moins une zone est comparable — sinon elle
                                // n'affiche que « insuffisant » trois fois.
                                if comparaisonPossible(section) {
                                    legende(section)
                                } else {
                                    Label(mentionRecul(section), systemImage: "hourglass")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } header: {
                                enTeteSection(section)
                            }
                        }

                        Section {
                            Label("45 derniers jours, \(CalculRatioObserve.effectifMinimalBucket) repas minimum par zone.", systemImage: "calendar")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Label("Repas ajusté (sport, hypo…) ou à contexte libre jamais compté.", systemImage: "minus.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Écart de ratio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    // MARK: - Depuis le changement de ratio

    /// Titre de section standard + badge date/effectif quand le ratio de
    /// cette section a déjà changé. `.textCase(nil)` contre-carre
    /// l'uppercase automatique des headers de `Form`, qui s'appliquerait
    /// sinon aussi au badge.
    @ViewBuilder
    private func enTeteSection(_ section: ObservationRatioSection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(CalculRatioObserve.libelleGroupe(section.groupe))
            Spacer(minLength: 8)
            if let apercu = apercusChangementRatio[section.groupe] {
                let jour = apercu.dateChangement.formatted(.dateTime.day().month(.abbreviated))
                Label("\(jour) · \(apercu.effectifDepuis) repas", systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .textCase(nil)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
        }
    }

    /// Dose moyenne + taux en cible (3h post-injection) avant/après le
    /// changement, ou un état « pas encore comparable » sous le seuil
    /// (`CalculDoseRatioChangement.effectifMinimalComparaison`).
    @ViewBuilder
    private func blocDepuisChangement(_ apercu: ApercuChangementRatio) -> some View {
        if let comparaison = apercu.comparaison {
            ligneComparaison(
                icone: "syringe",
                titre: "Dose moyenne",
                sousTitre: comparaison.avant.map { "vs avant le changement (\($0.doseMoyenne.doseInsulineFormatee))" }
                    ?? "aucun repas avant ce changement",
                valeur: comparaison.apres.doseMoyenne.doseInsulineFormatee,
                delta: comparaison.avant.map { pourcentageDelta(avant: $0.doseMoyenne, apres: comparaison.apres.doseMoyenne) }
            )
            ligneComparaison(
                icone: "target",
                titre: "En cible, 3h après l'injection",
                sousTitre: comparaison.avant.map { "contre \(pourcentageEntier($0.tauxBon)) % avant le changement" }
                    ?? "aucune comparaison avant ce changement",
                valeur: "\(pourcentageEntier(comparaison.apres.tauxBon)) %",
                delta: comparaison.avant.map { pointsDelta(avant: $0.tauxBon, apres: comparaison.apres.tauxBon) }
            )
        } else {
            Label("Pas encore comparable", systemImage: "hourglass")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("\(CalculDoseRatioChangement.effectifMinimalComparaison) repas minimum depuis le changement pour comparer")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ligneComparaison(icone: String, titre: String, sousTitre: String, valeur: String, delta: String?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: icone)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(titre)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(sousTitre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(valeur)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let delta {
                    Text(delta)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pourcentageEntier(_ taux: Double) -> Int {
        Int((taux * 100).rounded())
    }

    /// Écart relatif signé entre deux doses, en points de pourcentage
    /// entiers (« +12 % », « −8 % ») — signe typographique, même convention
    /// que `Double.ecartDoseFormate`.
    private func pourcentageDelta(avant: Double, apres: Double) -> String {
        guard avant > 0 else { return "—" }
        let delta = Int((((apres / avant) - 1) * 100).rounded())
        return delta < 0 ? "\u{2212}\(abs(delta)) %" : "+\(delta) %"
    }

    /// Écart signé en points de taux entre deux proportions déjà en 0…1
    /// (« +14 pts », « −6 pts »).
    private func pointsDelta(avant: Double, apres: Double) -> String {
        let delta = Int(((apres - avant) * 100).rounded())
        return delta < 0 ? "\u{2212}\(abs(delta)) pts" : "+\(delta) pts"
    }

    @ViewBuilder
    private func legende(_ section: ObservationRatioSection) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(TrancheRatio.allCases, id: \.self) { tranche in
                let bucket = section.buckets.first { $0.tranche == tranche }
                let etiquette = etiquette(tranche, section: section)
                // Signale explicitement quelle tranche tire le constat — sans
                // ça, repérer si le mieux est à gauche ou à droite demande de
                // comparer les 3 chiffres de tête. Deux cas : un écart
                // significatif détecté (bleu, « meilleur taux ») ou, faute
                // d'écart, le ratio actuel lui-même confirmé (vert, « ratio
                // confirmé ») — jamais les deux à la fois. Toute la colonne
                // (titre + chiffre + étiquette) est prise dans le bloc coloré,
                // pas seulement l'étiquette — pour que ce soit tout le
                // constat qui saute aux yeux, pas juste son label.
                VStack(spacing: 4) {
                    Text(libelleCourt(tranche))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(etiquette != nil ? .white : .secondary)
                        .multilineTextAlignment(.center)
                    if let bucket {
                        Text("\(bucket.bons)/\(bucket.total)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(etiquette != nil ? .white : Color.primary)
                    } else {
                        Text("insuffisant")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    if let etiquette {
                        Text(etiquette.texte)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(etiquette?.couleur ?? .clear, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
        }
    }

    /// Une comparaison n'a réellement eu lieu que si la tranche « proche » et
    /// au moins une tranche latérale ont franchi `effectifMinimalBucket` —
    /// sans ça il n'y a rien à confronter, et conclure « ratio confirmé »
    /// serait faux (c'était le cas avant : un groupe à 1 repas affichait un
    /// badge vert sur une colonne marquée « insuffisant »).
    private func comparaisonPossible(_ section: ObservationRatioSection) -> Bool {
        let aCentre = section.buckets.contains { $0.tranche == .doseProche }
        let aLateral = section.buckets.contains { $0.tranche != .doseProche }
        return aCentre && aLateral
    }

    private func etiquette(_ tranche: TrancheRatio, section: ObservationRatioSection) -> (texte: String, couleur: Color)? {
        if let ecart = section.ecart {
            return tranche == ecart.trancheOptimale ? ("meilleur taux", .blue) : nil
        }
        guard comparaisonPossible(section) else { return nil }
        return tranche == .doseProche ? ("ratio confirmé", .green) : nil
    }

    /// Phrase de repli quand aucune comparaison n'est possible — dit ce qu'on
    /// a, pas ce qu'on n'a pas.
    private func mentionRecul(_ section: ObservationRatioSection) -> String {
        let minimum = CalculRatioObserve.effectifMinimalBucket
        guard section.effectif > 0 else { return "Aucun repas analysé" }
        return "\(section.effectif) repas — \(minimum) minimum par zone pour comparer"
    }

    private func libelleCourt(_ tranche: TrancheRatio) -> String {
        switch tranche {
        case .doseNettementFaible: return "Dose plus faible"
        case .doseProche:          return "Ratio actuel"
        case .doseNettementForte:  return "Dose plus élevée"
        }
    }
}

// MARK: - Aperçus

private func _lot(groupe: SectionRepas?, bon: Int, total: Int, plage: ClosedRange<Double>) -> [EntreeRatioRepas] {
    // doseSuggeree: 10 pour glucides: 100 → ratio configuré affiché "1u/10g".
    // Les repas « pas bon » alternent moyen/mauvais, pour que le rouge
    // apparaisse aussi dans les previews, pas seulement l'orange.
    (0..<total).map { i in
        let ratio = plage.lowerBound + (plage.upperBound - plage.lowerBound) * Double(i) / Double(max(1, total - 1))
        let verdict: VerdictGlycemique = i < bon ? .bon : (i.isMultiple(of: 2) ? .moyen : .mauvais)
        return EntreeRatioRepas(
            id: UUID(), groupe: groupe, doseAppliquee: ratio * 10, doseSuggeree: 10,
            glucides: 100, verdict: verdict
        )
    }
}

private func _mockSections() -> [ObservationRatioSection] {
    let dejeuner = ObservationRatioSection(
        groupe: .dejeuner, effectif: 44,
        buckets: [
            BucketRatioObserve(tranche: .doseNettementFaible, total: 17, bons: 14),
            BucketRatioObserve(tranche: .doseProche, total: 20, bons: 11),
            BucketRatioObserve(tranche: .doseNettementForte, total: 7, bons: 3),
        ],
        ecart: EcartRatioObserve(bonsConfigure: 11, effectifConfigure: 20, trancheOptimale: .doseNettementFaible, bonsOptimal: 14, effectifOptimal: 17),
        entrees: _lot(groupe: .dejeuner, bon: 14, total: 17, plage: 0.55...0.78)
            + _lot(groupe: .dejeuner, bon: 11, total: 20, plage: 0.85...1.15)
            + _lot(groupe: .dejeuner, bon: 3, total: 7, plage: 1.22...1.55)
    )

    let diner = ObservationRatioSection(
        groupe: .diner, effectif: 38,
        buckets: [
            BucketRatioObserve(tranche: .doseProche, total: 25, bons: 12),
            BucketRatioObserve(tranche: .doseNettementForte, total: 13, bons: 10),
        ],
        ecart: EcartRatioObserve(bonsConfigure: 12, effectifConfigure: 25, trancheOptimale: .doseNettementForte, bonsOptimal: 10, effectifOptimal: 13),
        entrees: _lot(groupe: .diner, bon: 12, total: 25, plage: 0.85...1.15)
            + _lot(groupe: .diner, bon: 10, total: 13, plage: 1.25...1.5)
    )

    // Bien calibré, pas d'écart — illustre le badge « ratio confirmé ».
    let petitDejeuner = ObservationRatioSection(
        groupe: .petitDejeuner, effectif: 32,
        buckets: [
            BucketRatioObserve(tranche: .doseNettementFaible, total: 6, bons: 3),
            BucketRatioObserve(tranche: .doseProche, total: 20, bons: 14),
            BucketRatioObserve(tranche: .doseNettementForte, total: 6, bons: 3),
        ],
        ecart: nil,
        entrees: _lot(groupe: .petitDejeuner, bon: 3, total: 6, plage: 0.55...0.78)
            + _lot(groupe: .petitDejeuner, bon: 14, total: 20, plage: 0.85...1.15)
            + _lot(groupe: .petitDejeuner, bon: 3, total: 6, plage: 1.22...1.55)
    )

    return [dejeuner, diner, petitDejeuner]
}

/// Groupes trop peu fournis pour qu'une comparaison existe — aucun bucket,
/// donc aucun badge : c'est exactement le cas qui affichait à tort un
/// « ratio confirmé » vert sur une colonne « insuffisant ».
private func _mockSectionsSansComparaison() -> [ObservationRatioSection] {
    let dejeuner = ObservationRatioSection(
        groupe: .dejeuner, effectif: 1, buckets: [], ecart: nil,
        entrees: _lot(groupe: .dejeuner, bon: 1, total: 1, plage: 0.95...0.95)
    )
    let petitDejeuner = ObservationRatioSection(
        groupe: .petitDejeuner, effectif: 3, buckets: [], ecart: nil,
        entrees: _lot(groupe: .petitDejeuner, bon: 2, total: 2, plage: 0.92...1.05)
            + _lot(groupe: .petitDejeuner, bon: 0, total: 1, plage: 0.6...0.6)
    )
    return [dejeuner, petitDejeuner]
}

/// Centre fourni mais aucune tranche latérale : rien à confronter, donc pas
/// de badge « ratio confirmé » non plus.
private func _mockSectionCentreSeul() -> [ObservationRatioSection] {
    [ObservationRatioSection(
        groupe: .diner, effectif: 9,
        buckets: [BucketRatioObserve(tranche: .doseProche, total: 9, bons: 6)],
        ecart: nil,
        entrees: _lot(groupe: .diner, bon: 6, total: 9, plage: 0.85...1.15)
    )]
}

/// Un déjeuner comparable (assez de repas depuis le changement) et un dîner
/// tout juste changé (badge visible, bloc en « pas encore comparable »).
private func _mockApercusChangementRatio() -> [SectionRepas?: ApercuChangementRatio] {
    [
        .dejeuner: ApercuChangementRatio(
            dateChangement: Calendar.current.date(byAdding: .day, value: -18, to: Date()) ?? Date(),
            effectifDepuis: 23,
            comparaison: ComparaisonChangementRatio(
                dateChangement: Date(),
                avant: StatsPeriodeRatio(doseMoyenne: 6.6, tauxBon: 0.54, effectif: 20),
                apres: StatsPeriodeRatio(doseMoyenne: 5.8, tauxBon: 0.68, effectif: 23)
            )
        ),
        .diner: ApercuChangementRatio(
            dateChangement: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            effectifDepuis: 3,
            comparaison: nil
        ),
    ]
}

#if DEBUG
#Preview("Écart et ratio confirmé") {
    SheetEcartRatio(sections: _mockSections())
}

#Preview("Depuis le changement de ratio") {
    SheetEcartRatio(sections: _mockSections(), apercusChangementRatio: _mockApercusChangementRatio())
}

#Preview("Trop peu de repas") {
    SheetEcartRatio(sections: _mockSectionsSansComparaison())
}

#Preview("Centre seul, rien à comparer") {
    SheetEcartRatio(sections: _mockSectionCentreSeul())
}

#Preview("Mix comparable / non comparable") {
    SheetEcartRatio(sections: _mockSections() + _mockSectionsSansComparaison())
}

#Preview("Aucune donnée") {
    SheetEcartRatio(sections: [])
}

#Preview("Sombre") {
    SheetEcartRatio(sections: _mockSections())
        .preferredColorScheme(.dark)
}
#endif
