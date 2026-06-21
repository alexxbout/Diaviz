//
//  GrapheJourneeSport.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI
import Charts

/// Timeline 24h des activités sportives du jour, paginée jour par jour.
///
/// Encodage des barres :
/// - **Position X** : heure de début de l'activité
/// - **Hauteur**    : durée en minutes
/// - **Couleur**    : catégorie (cardio rouge / muscu violet / autre bleu)
/// - **Annotation** : durée formatée au sommet de chaque barre
///
/// Architecture inspirée de `GrapheJourneeMedications` :
/// - `ScrollView` horizontale paginée (un Chart par jour) avec
///   `.scrollTargetBehavior(.paging)`.
/// - Légende des catégories posée sous le graphe.
/// - Tap sur une barre : remonte au parent via `onTapActivite` qui
///   peut faire défiler la liste vers la row correspondante.
struct GrapheJourneeSport: View {

    // MARK: - Paramètres

    /// Toutes les activités multi-jours.
    let activites: [ActiviteSportive]

    /// Date sélectionnée — bindée au parent qui l'utilise pour filtrer
    /// la liste.
    @Binding var selectedDate: Date

    /// Callback quand l'utilisateur tape une barre : le parent peut
    /// alors faire défiler la liste vers la row correspondante.
    var onTapActivite: ((ActiviteSportive) -> Void)? = nil

    // MARK: - État interne

    private let localeFr = Locale(identifier: "fr_FR")

    /// Plage de jours navigables : 30 derniers jours (today en dernier).
    /// Calculé une fois — la liste est stable sur la durée d'affichage.
    private let jours: [Date] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }
    }()

    /// Jour actuellement centré dans la `ScrollView`.
    @State private var dateScroll: Date?

    /// Progression de l'animation d'apparition (0 → 1). Multipliée
    /// sur la hauteur des barres pour les faire pousser depuis la
    /// baseline lors du premier affichage.
    @State private var progressionApparition: Double = 0

    private let hauteurChart: CGFloat = 180

    // MARK: - Calculs dérivés

    private var dateAffichee: Date {
        dateScroll ?? jours.last ?? Date()
    }

    /// Activités d'un jour donné, triées par heure de début.
    private func activitesPour(jour: Date) -> [ActiviteSportive] {
        let cal = Calendar.current
        return activites
            .filter { cal.isDate($0.dateDebut, inSameDayAs: jour) }
            .sorted { $0.dateDebut < $1.dateDebut }
    }

    private func domainePour(jour: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        let debut = cal.startOfDay(for: jour)
        let fin = cal.date(byAdding: .day, value: 1, to: debut) ?? debut.addingTimeInterval(86400)
        return debut...fin
    }

    /// Borne supérieure de l'axe Y — palier de 15min au-dessus de la
    /// durée max + un palier de marge (minimum 30min). La marge garantit
    /// que l'annotation au sommet reste dans la zone de tracé.
    private func maxY(pour activites: [ActiviteSportive]) -> Double {
        let max = activites.map(\.dureeMinutes).max() ?? 0
        let palier = ((max / 15) + 1) * 15
        return Swift.max(Double(palier), 30)
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

    private var activitesAffichees: [ActiviteSportive] {
        activitesPour(jour: dateAffichee)
    }

    /// Durée totale du jour en minutes — somme brute des durées (les
    /// activités peuvent se chevaucher en théorie mais ça reste l'info
    /// la plus parlante pour l'utilisateur).
    private var totalMinutes: Int {
        activitesAffichees.reduce(0) { $0 + $1.dureeMinutes }
    }

    /// Résumé compact par catégorie — « 1 cardio · 1 autre ».
    private var resumeCategories: String {
        let act = activitesAffichees
        let parts = CategorieSport.allCases.compactMap { cat -> String? in
            let n = act.filter { $0.type.categorie == cat }.count
            guard n > 0 else { return nil }
            return "\(n) \(cat.libelle.lowercased())"
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Corps

    var body: some View {
        if activites.isEmpty {
            carteVide
        } else {
            contenu
        }
    }

    // MARK: - État vide épuré

    /// Carte affichée quand **aucune** activité n'existe sur la période :
    /// titre + message centré, sans l'en-tête « Aucune activité » redondant
    /// et sans navigation — on évite le graphe-squelette chargé qui
    /// n'affichait rien. Le graphe complet revient dès qu'une activité
    /// existe (même sur un autre jour).
    private var carteVide: some View {
        VStack(alignment: .leading, spacing: 12) {
            titre
            etatVide
                .frame(height: hauteurChart)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var contenu: some View {
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
            // Petite pause avant de jouer l'apparition pour laisser le
            // temps à la ScrollView de se positionner sur le dernier
            // jour — sinon les barres animent depuis la mauvaise page.
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
    // hauteur (durée) + couleur (catégorie). Marqué comme heading pour
    // VoiceOver, qui le lira avant le reste du graphe et permettra à
    // l'utilisateur de comprendre le contexte avant les chiffres.
    private var titre: some View {
        Text("Durée et type d'activité")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - En-tête

    private var entete: some View {
        let act = activitesAffichees
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

            if !act.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(act.count) activité\(act.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    if !resumeCategories.isEmpty {
                        Text(resumeCategories)
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
        // Jour sans activité : pas de chiffre « Aucune activité » dans
        // l'en-tête — le message centré du graphe vide suffit, on garde
        // l'en-tête léger (juste la date).
        if !activitesAffichees.isEmpty {
            Text(formaterDuree(totalMinutes))
                .font(.system(size: 36, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: dateAffichee)
        }
    }

    // MARK: - Pages scrollables

    private var pages: some View {
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
        .frame(height: hauteurChart)
    }

    @ViewBuilder
    private func pagePour(jour: Date) -> some View {
        let activitesJour = activitesPour(jour: jour)
        if activitesJour.isEmpty {
            etatVide
        } else {
            chartPour(jour: jour, activites: activitesJour)
        }
    }

    private var etatVide: some View {
        ContentUnavailableView(
            "Aucune activité",
            systemImage: "figure.run",
            description: Text("Vos séances du jour apparaîtront ici")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chart 24h en barres

    @ViewBuilder
    private func chartPour(jour: Date, activites: [ActiviteSportive]) -> some View {
        Chart {
            ForEach(activites) { activite in
                let hauteur = Double(activite.dureeMinutes) * progressionApparition
                BarMark(
                    x: .value("Heure", activite.dateDebut),
                    y: .value("Durée", hauteur),
                    width: .fixed(10)
                )
                .foregroundStyle(activite.type.categorie.couleur.gradient)
                .cornerRadius(6)
                .annotation(position: .top, spacing: 2) {
                    Text(formaterDureeBarre(activite.dureeMinutes))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(activite.type.categorie.couleur)
                        .monospacedDigit()
                }
            }
        }
        .chartXScale(domain: domainePour(jour: jour))
        .chartYScale(domain: 0...maxY(pour: activites))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().locale(localeFr))
            }
        }
        // Axe Y des durées à droite — cohérent visuellement avec la
        // page Médications (axe des unités d'insuline aussi à droite).
        // L'échelle est pilotée par `maxY(pour:)` ; `desiredCount: 4`
        // laisse Charts choisir des graduations « rondes » (15/30/45,
        // 30/60/90, etc.) sans qu'on ait à les calculer à la main.
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let duree = value.as(Int.self) {
                        Text("\(duree) min")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        // Overlay tap : convertit la position du tap en heure puis
        // cherche l'activité la plus proche. On évite `.chartGesture`
        // (plus rigide) au profit d'un `chartOverlay` qui donne la
        // proxy ainsi que la vue d'ancrage.
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let plotRect = geo[plotFrame]
                        let x = location.x - plotRect.origin.x
                        guard x >= 0, x <= plotRect.width else { return }
                        if let date: Date = proxy.value(atX: x) {
                            tapAuPlusProche(date: date, parmi: activites)
                        }
                    }
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: progressionApparition)
    }

    /// Cherche l'activité la plus proche du tap (≤ 1h d'écart), puis
    /// la remonte au parent. Le seuil 1h évite de matcher une barre
    /// éloignée quand l'utilisateur tape dans une zone vide.
    private func tapAuPlusProche(date: Date, parmi activites: [ActiviteSportive]) {
        let proche = activites.min(by: {
            abs($0.dateDebut.timeIntervalSince(date)) < abs($1.dateDebut.timeIntervalSince(date))
        })
        guard let proche,
              abs(proche.dateDebut.timeIntervalSince(date)) <= 3600 else { return }
        onTapActivite?(proche)
    }

    // MARK: - Légende

    /// Catégories effectivement présentes dans la journée affichée.
    /// Triées par `rawValue` pour un ordre stable d'un jour à l'autre
    /// (la `Set` ne préserverait pas l'ordre des éléments insérés).
    private var categoriesActivesAujourdhui: [CategorieSport] {
        let presentes = Set(activitesAffichees.map(\.type.categorie))
        return presentes.sorted { $0.rawValue < $1.rawValue }
    }

    /// Légende dynamique — uniquement les catégories qui ont au moins
    /// une activité dans le jour courant. Évite le bruit visuel d'une
    /// légende qui annoncerait des couleurs absentes du graphe.
    /// Vue intentionnellement vide quand le jour n'a aucune activité :
    /// le `chiffreCle` "Aucune activité" porte déjà l'info.
    @ViewBuilder
    private var legende: some View {
        let categories = categoriesActivesAujourdhui
        if !categories.isEmpty {
            HStack(spacing: 16) {
                Spacer()
                ForEach(categories, id: \.self) { cat in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(cat.couleur)
                            .frame(width: 6, height: 6)
                        Text(cat.libelle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    /// Format compact pour le chiffre clé en en-tête : « 75 min » ou
    /// « 1h15 ». L'en-tête a la place pour le format lisible.
    private func formaterDuree(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    /// Format ultra-compact pour l'annotation au sommet d'une barre :
    /// toujours en minutes (« 45min », « 90min ») — plus court que
    /// « 1h30 » et plus comparable d'une barre à l'autre.
    private func formaterDureeBarre(_ minutes: Int) -> String {
        "\(minutes)min"
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
    let activites = ActivitesSportService.echantillonsApercu()
    return ScrollView {
        VStack(spacing: 0) {
            GrapheJourneeSport(activites: activites, selectedDate: $date)
            Color(.systemGroupedBackground).frame(height: 600)
        }
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Journée vide") {
    @Previewable @State var date = Calendar.current.startOfDay(for: Date())
    return ScrollView {
        VStack(spacing: 0) {
            GrapheJourneeSport(activites: [], selectedDate: $date)
            Color(.systemGroupedBackground).frame(height: 600)
        }
    }
    .background(Color(.systemGroupedBackground))
}
