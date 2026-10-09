//
//  PageEcartRatio.swift
//  diaviz
//

import SwiftUI

/// Page de détail du ratio observé par R1 — poussée depuis la carte
/// d'insight et depuis `CarteAnalyseRatio`. Un moment à la fois (barre
/// Liquid Glass en bas), un graphique en gélules (`GraphiqueGelulesRatio`) et
/// un score en tête mis à jour au toucher. Voir doc R1 « Graphique en gélules ».
struct PageEcartRatio: View {

    let sections: [ObservationRatioSection]
    /// Comparaison dose/verdict avant-après le dernier changement de ratio,
    /// par section — absente pour une section jamais modifiée (badge et bloc
    /// masqués, section inchangée). Défaut vide pour ne pas casser les
    /// appelants existants.
    var apercusChangementRatio: [SectionRepas?: ApercuChangementRatio] = [:]
    /// Ventilation par moment — sert seulement à dire combien de repas ont
    /// été écartés et pourquoi. Vide = ligne de décompte masquée.
    var repartitions: [SectionRepas?: RepartitionRepasMoment] = [:]

    /// Moment affiché — une seule carte à la fois, choisie dans la barre du bas.
    @State private var groupeChoisi: SectionRepas??
    /// Ratio touché sur le graphique ; `nil` = ratio configuré.
    @State private var ratioChoisi: Int?

    private var section: ObservationRatioSection? {
        guard let groupeChoisi else { return sections.first }
        return sections.first { $0.groupe == groupeChoisi } ?? sections.first
    }

    var body: some View {
        Group {
            if let section {
                contenu(section)
            } else {
                ContentUnavailableView(
                    "Pas encore de résultat",
                    systemImage: "chart.bar",
                    description: Text("Aucun moment n'a encore assez de repas analysés pour être comparé." + (decompteEcartesFenetre.map { " " + $0 } ?? ""))
                )
            }
        }
        .navigationTitle("Écart de ratio")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func contenu(_ section: ObservationRatioSection) -> some View {
        let ratio = ratioConfigure(section)
        let colonnes = ColonneRatio.colonnes(entrees: section.entrees, ratioConfigure: ratio)
        let cible = ratioChoisi ?? ratio
        let colonne = colonnes.first { $0.grammesParUnite == cible }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                score(colonne: colonne, grammes: cible, estActuel: cible == ratio)

                VStack(alignment: .leading, spacing: 12) {
                    // `.id` : un changement de moment reconstruit le graphique
                    // au lieu d'animer les gélules d'un moment vers l'autre.
                    GraphiqueGelulesRatio(
                        colonnes: colonnes, ratioConfigure: ratio,
                        selection: Binding(get: { cible }, set: { ratioChoisi = $0 })
                    )
                    .id(section.groupe)
                    HStack {
                        Text("← moins d'insuline")
                        Spacer()
                        Text("plus d'insuline →")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    legendeCouleurs
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.large))

                if comparaisonPossible(section) {
                    legende(section)
                        .padding(16)
                        .glassEffect(.regular, in: .rect(cornerRadius: Radius.large))
                }

                if let apercu = apercusChangementRatio[section.groupe] {
                    VStack(alignment: .leading, spacing: 10) {
                        let jour = apercu.dateChangement.formatted(.dateTime.day().month(.abbreviated))
                        Text("Depuis le changement du \(jour)")
                            .font(.subheadline.weight(.semibold))
                        blocDepuisChangement(apercu)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: Radius.large))
                }

                carteEcartes(section)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Une gélule par ratio réellement appliqué. Sa hauteur suit le nombre de repas, ses couleurs leurs résultats. Le ratio actuel est entouré.", systemImage: "capsule.portrait")
                    Label("45 derniers jours, \(CalculRatioObserve.effectifMinimalBucket) repas minimum par zone pour comparer.", systemImage: "calendar")
                    Label("Jamais comptés : repas ajusté ou à contexte libre, ou dont la courbe ne mesure pas que lui — autre repas dans les 4 h, insuline encore active, correction (même faite avec le repas), resucrage ou sport entre 1 h avant et 4 h après.", systemImage: "line.diagonal")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(fond(colonne: colonnes.first { $0.grammesParUnite == ratio }))
        .safeAreaInset(edge: .bottom) { barreMoments }
    }

    // MARK: - Score

    private func score(colonne: ColonneRatio?, grammes: Int?, estActuel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(grammes.map { estActuel ? "À ton ratio actuel, 1u/\($0)g" : "À 1u/\($0)g" } ?? "Ratio non configuré")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(colonne.flatMap { $0.total > 0 ? "\(Int((100 * Double($0.enCible) / Double($0.total)).rounded())) %" : nil } ?? "—")
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(colonne.flatMap { $0.total > 0 ? "en cible · \($0.enCible) sur \($0.total) repas" : nil } ?? "aucun repas à ce ratio")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var legendeCouleurs: some View {
        HStack(spacing: 12) {
            pastille("en cible", .green)
            pastille("pic modéré", .orange)
            pastille("hyper", RaisonMauvaisVerdict.hyperglycemie.couleur)
            pastille("hypo", RaisonMauvaisVerdict.hypoglycemie.couleur)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func pastille(_ texte: String, _ couleur: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(couleur).frame(width: 8, height: 8)
            Text(texte)
        }
    }

    /// Fond teinté par la réussite au ratio actuel — vert, orange ou rouge
    /// très diffus, gris sans repas. Le verre des cartes le laisse deviner.
    private func fond(colonne: ColonneRatio?) -> some View {
        let teinte: Color = {
            guard let colonne, colonne.total > 0 else { return .gray }
            let taux = Double(colonne.enCible) / Double(colonne.total)
            return taux >= 0.65 ? .green : taux >= 0.4 ? .orange : .red
        }()
        return LinearGradient(colors: [teinte.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea()
    }

    private func ratioConfigure(_ section: ObservationRatioSection) -> Int? {
        guard let e = section.entrees.first(where: { $0.doseSuggeree > 0 }) else { return nil }
        return Int((Double(e.glucides) / e.doseSuggeree).rounded())
    }

    // MARK: - Moments

    private var barreMoments: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                ForEach(sections, id: \.groupe) { s in
                    let actif = s.groupe == section?.groupe
                    Button {
                        // Sans animation : le score et les gélules du nouveau
                        // moment apparaissent d'un coup, sans glisser.
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) {
                            groupeChoisi = .some(s.groupe)
                            ratioChoisi = nil
                        }
                    } label: {
                        Text(CalculRatioObserve.libelleGroupe(s.groupe))
                            .font(.footnote.weight(actif ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(actif ? Color.primary.opacity(0.12) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .opacity(sections.count > 1 ? 1 : 0)
    }

    // MARK: - Repas écartés

    @ViewBuilder
    private func carteEcartes(_ section: ObservationRatioSection) -> some View {
        if let r = repartitions[section.groupe], r.ecartes + r.ratioSportEnVigueur > 0 {
            let ecartes = r.ecartes + r.ratioSportEnVigueur
            let motifs: [(String, Int)] = RaisonExclusionFenetre.allCases.compactMap { raison in
                    r.parRaisonFenetre[raison].map { (raison.libelle, $0) }
                } + [("ajusté", r.ajustes), ("contexte libre", r.contexteLibre),
                     ("ratio sport", r.ratioSportEnVigueur), ("exclu à la main", r.exclusManuellement)]
                    .filter { $0.1 > 0 }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(ecartes) repas écarté\(ecartes > 1 ? "s" : "")")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(r.total) au total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                FlowChips(items: motifs.map { "\($0.0) ×\($0.1)" })
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.large))
        }
    }


    /// « 7 repas écartés pour ces raisons : autre repas ×4, … » — une raison
    /// par repas et par cause, donc la somme peut dépasser le total.
    private var decompteEcartesFenetre: String? {
        let total = repartitions.values.reduce(0) { $0 + $1.pollues }
        guard total > 0 else { return nil }
        let parRaison = RaisonExclusionFenetre.allCases.compactMap { raison -> String? in
            let n = repartitions.values.reduce(0) { $0 + ($1.parRaisonFenetre[raison] ?? 0) }
            return n > 0 ? "\(raison.libelle) ×\(n)" : nil
        }
        let repas = total > 1 ? "repas écartés" : "repas écarté"
        return "\(total) \(repas) pour ces raisons : " + parRaison.joined(separator: ", ") + "."
    }

    // MARK: - Depuis le changement de ratio

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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 28, height: 28)

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
    NavigationStack { PageEcartRatio(sections: _mockSections()) }
}

#Preview("Depuis le changement de ratio") {
    NavigationStack {
        PageEcartRatio(sections: _mockSections(), apercusChangementRatio: _mockApercusChangementRatio())
    }
}

#Preview("Trop peu de repas") {
    NavigationStack { PageEcartRatio(sections: _mockSectionsSansComparaison()) }
}

#Preview("Centre seul, rien à comparer") {
    NavigationStack { PageEcartRatio(sections: _mockSectionCentreSeul()) }
}

#Preview("Mix comparable / non comparable") {
    NavigationStack { PageEcartRatio(sections: _mockSections() + _mockSectionsSansComparaison()) }
}

#Preview("Aucune donnée") {
    NavigationStack { PageEcartRatio(sections: []) }
}

#Preview("Sombre") {
    NavigationStack { PageEcartRatio(sections: _mockSections()) }
        .preferredColorScheme(.dark)
}
#endif


/// Puces qui passent à la ligne — motifs d'exclusion.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayoutChips(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }
}

private struct FlowLayoutChips: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, ligne: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x + t.width > largeur, x > 0 { x = 0; y += ligne + spacing; ligne = 0 }
            x += t.width + spacing; ligne = max(ligne, t.height)
        }
        return CGSize(width: largeur.isFinite ? largeur : x, height: y + ligne)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, ligne: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x + t.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += ligne + spacing; ligne = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += t.width + spacing; ligne = max(ligne, t.height)
        }
    }
}
