//
//  GrapheJourneeMedications.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI
import Charts

/// Timeline 24h des médications du jour, paginée jour par jour.
///
/// Encodage des barres :
/// - **Position X** : heure de l'injection
/// - **Hauteur**    : dose en unités d'insuline
/// - **Couleur**    : type (bleu lente / violet repas / orange correction)
/// - **Annotation** : valeur de la dose au sommet de chaque barre
///
/// Architecture :
/// - couche scrollable horizontale paginée (un Chart par jour)
/// - couche fixe (`legendeFixe`) qui affiche l'axe Y sur le bord droit
/// - légende des types posée sous le graphe
struct GrapheJourneeMedications: View {

    // MARK: - Paramètres

    /// Toutes les injections multi-jours (rapide + lente).
    let injections: [Injection]

    /// Date sélectionnée — bindée au parent qui l'utilise pour filtrer
    /// la carte lente, les listes corrections et bolus repas.
    @Binding var selectedDate: Date

    // MARK: - État interne

    private let localeFr = Locale(identifier: "fr_FR")

    /// Plage de jours navigables : 30 derniers jours (today en dernier).
    private let jours: [Date] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }
    }()

    /// Jour actuellement centré dans la `ScrollView`.
    @State private var dateScroll: Date?

    /// Progression de l'animation d'apparition (0 → 1). Multipliée sur la
    /// hauteur des barres pour les faire pousser depuis la baseline lors
    /// du premier affichage du graphe.
    @State private var progressionApparition: Double = 0

    private let hauteurChart: CGFloat = 180

    /// Largeur réservée à la légende Y fixée sur le bord droit.
    private let legendWidth: CGFloat = 56
    private let legendMarge: CGFloat = 12

    // MARK: - Calculs dérivés

    private var dateAffichee: Date {
        dateScroll ?? jours.last ?? Date()
    }

    /// Injections d'un jour donné, triées par heure (rapide + lente).
    private func injectionsPour(jour: Date) -> [Injection] {
        let cal = Calendar.current
        return injections
            .filter { cal.isDate($0.heure, inSameDayAs: jour) }
            .sorted { $0.heure < $1.heure }
    }

    private func domainePour(jour: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        let debut = cal.startOfDay(for: jour)
        let fin = cal.date(byAdding: .day, value: 1, to: debut) ?? debut.addingTimeInterval(86400)
        return debut...fin
    }

    /// Groupe d'injections données simultanément (même minute). Permet
    /// de rendre une seule barre empilée pour le cas fréquent « repas
    /// + correction en une piqûre ».
    private struct GroupeInjections: Identifiable {
        let heure: Date
        /// Ordonnées du bas vers le haut de la pile (cf. `ordreEmpilement`).
        let parts: [Injection]
        var id: Date { heure }
        var doseTotale: Double { parts.reduce(0) { $0 + $1.dose } }
    }

    /// Groupe les injections par minute. Les rapide qui partagent la
    /// même minute fusionnent dans un seul groupe (repas en bas,
    /// correction au-dessus). La lente se retrouve en groupe singleton
    /// en pratique — elle n'a pas vocation à coïncider avec un rapide.
    private func grouperInjections(_ injections: [Injection]) -> [GroupeInjections] {
        let cal = Calendar.current
        let parMinute = Dictionary(grouping: injections) { inj -> Date in
            cal.date(bySetting: .second, value: 0, of: inj.heure) ?? inj.heure
        }
        return parMinute
            .map { (heure, parts) in
                GroupeInjections(
                    heure: heure,
                    parts: parts.sorted { ordreEmpilement($0.type) < ordreEmpilement($1.type) }
                )
            }
            .sorted { $0.heure < $1.heure }
    }

    /// Ordre d'empilement bas → haut : repas en bas (la dose
    /// « principale »), correction au-dessus (l'« ajout »).
    private func ordreEmpilement(_ type: TypeInsuline) -> Int {
        switch type {
        case .rapideRepas:       0
        case .rapideCorrection:  1
        case .lente:             2
        }
    }

    /// Borne supérieure de l'axe Y pour un set d'injections — palier
    /// de 5u au-dessus de la **dose totale max d'un groupe** + un palier
    /// de marge (minimum 10u). On prend la somme par groupe parce que
    /// les barres empilées montent jusqu'à `dose_repas + dose_correction`.
    /// La marge garantit que l'annotation au sommet reste dans la zone
    /// de tracé.
    private func maxY(pour injections: [Injection]) -> Double {
        let max = grouperInjections(injections)
            .map(\.doseTotale)
            .max() ?? 0
        let palier = ((Int(max) / 5) + 1) * 5
        return Swift.max(Double(palier), 10)
    }

    /// Borne Y du jour actuellement affiché — utilisée par la
    /// `legendeFixe`. Se met à jour quand l'utilisateur scroll d'un
    /// jour à l'autre.
    private var maxYAffiche: Double {
        maxY(pour: injectionsPour(jour: dateAffichee))
    }

    private var libelleJour: String {
        let cal = Calendar.current
        if cal.isDateInToday(dateAffichee) { return "Aujourd'hui" }
        if cal.isDateInYesterday(dateAffichee) { return "Hier" }
        return dateAffichee.formatted(
            Date.FormatStyle()
                .weekday(.wide)
                .day()
                .month(.wide)
                .locale(localeFr)
        ).capitalized
    }

    private var injectionsAffichees: [Injection] {
        injectionsPour(jour: dateAffichee)
    }

    /// Total rapide du jour affiché — la lente est exclue car
    /// structurellement différente (une dose stable de fond).
    private var totalRapide: Double {
        injectionsAffichees
            .filter { $0.type != .lente }
            .reduce(0) { $0 + $1.dose }
    }

    /// Résumé compact par type — « 1 lente · 2 cor. · 3 repas ».
    private var resumeTypes: String {
        let inj = injectionsAffichees
        let lente = inj.filter { $0.type == .lente }.count
        let cor = inj.filter { $0.type == .rapideCorrection }.count
        let repas = inj.filter { $0.type == .rapideRepas }.count

        var parts: [String] = []
        if lente > 0  { parts.append("\(lente) \(TypeInsuline.lente.libelleAbrege)") }
        if cor > 0    { parts.append("\(cor) \(TypeInsuline.rapideCorrection.libelleAbrege)") }
        if repas > 0  { parts.append("\(repas) \(TypeInsuline.rapideRepas.libelleAbrege)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Corps

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titre
            entete
            pages
            legende
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .onAppear {
            if dateScroll == nil { dateScroll = jours.last }
        }
        .task {
            progressionApparition = 0
            try? await Task.sleep(for: .milliseconds(80))
            progressionApparition = 1
        }
        .onChange(of: dateScroll) { _, nouvelle in
            if let nouvelle { selectedDate = nouvelle }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: changerJour(de: -1)
            case .decrement: changerJour(de: 1)
            @unknown default: break
            }
        }
    }

    // MARK: - Titre du graphe
    //
    // Sous-titre éditorial qui décrit ce que le graphe représente —
    // hauteur (dose) + couleur (type d'insuline). Marqué comme heading
    // pour VoiceOver, qui le lira avant le reste du graphe et permettra
    // à l'utilisateur de comprendre le contexte avant les chiffres.
    private var titre: some View {
        Text("Dose et type d'insuline")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - En-tête

    private var entete: some View {
        let inj = injectionsAffichees
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(libelleJour)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: libelleJour)

                chiffreCle
            }

            Spacer()

            if !inj.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(inj.count) injection\(inj.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    if !resumeTypes.isEmpty {
                        Text(resumeTypes)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chiffreCle: some View {
        if injectionsAffichees.isEmpty {
            Text("Aucune donnée")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tertiary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formate(totalRapide))
                    .font(.system(size: 36, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("u rapide")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .animation(.easeOut(duration: 0.2), value: dateAffichee)
        }
    }

    // MARK: - Pages scrollables + légende Y fixe

    private var pages: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(jours, id: \.self) { jour in
                        pagePour(jour: jour)
                            .containerRelativeFrame(.horizontal)
                            .id(jour)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $dateScroll)
            .scrollIndicators(.hidden)

            legendeFixe
        }
        .frame(height: hauteurChart)
    }

    /// Bande Y fixe alignée sur le bord droit. Chart fantôme partageant
    /// la même `chartYScale` que les pages, avec un fond opaque qui
    /// masque les barres qui passent en dessous pendant le scroll. Le
    /// padding bas (24pt) compense la hauteur naturelle de l'axe X côté
    /// barres pour que les graduations Y restent alignées avec la
    /// baseline du plot.
    private var legendeFixe: some View {
        let domaine = maxYAffiche
        return Chart {
            BarMark(
                x: .value("h", Calendar.current.startOfDay(for: Date())),
                y: .value("u", domaine)
            )
            .opacity(0)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...domaine)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .stride(by: 5)) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v) u")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.padding(.bottom, 24)
        }
        .frame(width: legendWidth)
        .padding(.trailing, legendMarge)
        .background(Color(.secondarySystemGroupedBackground))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pagePour(jour: Date) -> some View {
        let injectionsJour = injectionsPour(jour: jour)
        if injectionsJour.isEmpty {
            etatVide
                .padding(.trailing, legendWidth + legendMarge)
        } else {
            chartPour(jour: jour, injections: injectionsJour)
        }
    }

    private var etatVide: some View {
        ContentUnavailableView(
            "Aucune injection",
            systemImage: "syringe",
            description: Text("Vos injections du jour apparaîtront ici")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chart 24h en barres

    @ViewBuilder
    private func chartPour(jour: Date, injections: [Injection]) -> some View {
        Chart {
            ForEach(grouperInjections(injections)) { groupe in
                ForEach(Array(groupe.parts.enumerated()), id: \.element.id) { idx, part in
                    let estSommet = idx == groupe.parts.count - 1
                    let hauteur = part.dose * progressionApparition
                    BarMark(
                        x: .value("Heure", groupe.heure),
                        y: .value("Dose", hauteur),
                        width: .fixed(10)
                    )
                    .foregroundStyle(part.type.couleur.gradient)
                    // Coins arrondis uniquement en haut de la pile pour
                    // éviter un joint arrondi entre deux portions empilées.
                    .cornerRadius(estSommet ? 6 : 0)
                    .annotation(position: .top, spacing: 2) {
                        if estSommet {
                            annotationGroupe(groupe)
                        }
                    }
                }
            }
        }
        .chartXScale(domain: domainePour(jour: jour))
        .chartYScale(domain: 0...maxY(pour: injections))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().locale(localeFr))
            }
        }
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.trailing, legendWidth + legendMarge)
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: progressionApparition)
    }

    /// Annotation au sommet d'une barre composée — une `Text` par partie
    /// dans la couleur sémantique de son type. Pour un groupe singleton
    /// (cas standard), une seule valeur est rendue ; pour un groupe à
    /// deux portions (repas + correction), les deux valeurs s'alignent.
    @ViewBuilder
    private func annotationGroupe(_ groupe: GroupeInjections) -> some View {
        HStack(spacing: 3) {
            ForEach(groupe.parts) { part in
                Text("\(part.dose, specifier: "%.1f")u")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(part.type.couleur)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Légende

    /// Légende des couleurs sous le graphe — tous les types représentés
    /// dans le chart.
    private var legende: some View {
        HStack(spacing: 20) {
            Spacer()
            ForEach(TypeInsuline.allCases, id: \.self) { t in
                HStack(spacing: 6) {
                    Circle()
                        .fill(t.couleur)
                        .frame(width: 6, height: 6)
                    Text(t.libelle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }

    private func changerJour(de delta: Int) {
        guard let courant = dateScroll,
              let idx = jours.firstIndex(of: courant) else { return }
        let nouvelIndex = idx + delta
        guard nouvelIndex >= 0 && nouvelIndex < jours.count else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dateScroll = jours[nouvelIndex]
        }
    }
}

// MARK: - Aperçu

#Preview("Journée typique") {
    @Previewable @State var date = Calendar.current.startOfDay(for: Date())
    let injections = InjectionsServiceMock.shared.injections
    return ScrollView {
        VStack(spacing: 0) {
            GrapheJourneeMedications(
                injections: injections,
                selectedDate: $date
            )
            Color(.systemGroupedBackground).frame(height: 600)
        }
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Journée vide") {
    @Previewable @State var date = Calendar.current.startOfDay(for: Date())
    return ScrollView {
        VStack(spacing: 0) {
            GrapheJourneeMedications(
                injections: [],
                selectedDate: $date
            )
            Color(.systemGroupedBackground).frame(height: 600)
        }
    }
    .background(Color(.systemGroupedBackground))
}
