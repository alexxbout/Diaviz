//
//  GraphRepasJournee.swift
//  insulog
//
//  Created by Alexandre on 30/04/2026.
//

import SwiftUI
import Charts

/// Graphique 24h des repas, façon Apple Health.
///
/// Architecture en deux couches :
/// - Une couche "fixe" qui dessine la légende de l'axe Y, toujours rendue
///   par un `Chart` "fantôme" sans barres, mais avec le même `chartYScale`
///   que les pages scrollables.
/// - Une couche scrollable horizontale paginée, dans laquelle chaque page
///   est un `Chart` qui ne rend que ses `BarMark` (axe Y masqué).
///
/// Encodage sémantique des barres :
/// - **Hauteur** = quantité de glucides
/// - **Couleur** = verdict glycémique (vert / orange / rouge / gris)
/// - **Opacité** = présence d'injection (1.0 avec, 0.4 sans)
/// - **Tap** = popup détaillant heure, glucides, verdict, et délai depuis
///   le dernier repas avec injection.
struct GraphRepasJournee: View {

    /// Tous les repas projetés pour le graphe (multi-jours, plats).
    /// Le composant filtre lui-même par jour.
    let repas: [RepasGraph]

    /// Date sélectionnée — liée au parent pour qu'il puisse filtrer
    /// son contenu (liste de repas) sur la même journée.
    @Binding var selectedDate: Date

    private let localeFr = Locale(identifier: "fr_FR")

    /// Plage de jours navigables : les 30 derniers jours, du plus ancien
    /// au plus récent (today en dernier).
    private let jours: [Date] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }
    }()

    /// ID (= Date) du jour actuellement centré dans la `ScrollView`.
    @State private var dateScroll: Date?

    /// Repas actuellement tappé pour afficher le popup.
    @State private var repasSelectionne: RepasGraph?

    /// Présentation du sheet expliquant la sémantique du graphe.
    @State private var afficheInfo = false

    /// Hauteur réservée à la zone chart (excl. en-tête).
    private let hauteurChart: CGFloat = 180

    /// Largeur de la bande qui contient la légende Y droite.
    private let legendWidth: CGFloat = 56
    private let legendMarge: CGFloat = 12

    private var dateAffichee: Date {
        dateScroll ?? jours.last ?? Date()
    }

    /// Borne supérieure stable de l'axe Y, arrondie au pallier supérieur de
    /// 25g (pour aligner avec les graduations), avec un minimum de 100g.
    private var maxY: Int {
        let max = repas.map(\.glucides).max().map(Int.init) ?? 0
        let palier = ((max / 25) + 1) * 25
        return Swift.max(palier, 100)
    }

    private func repasPour(jour: Date) -> [RepasGraph] {
        let cal = Calendar.current
        return repas
            .filter { cal.isDate($0.heure, inSameDayAs: jour) }
            .sorted { $0.heure < $1.heure }
    }

    private func domainePour(jour: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        let debut = cal.startOfDay(for: jour)
        let fin = cal.date(byAdding: .day, value: 1, to: debut) ?? debut.addingTimeInterval(86400)
        return debut...fin
    }

    private var libelleJour: String {
        let cal = Calendar.current
        if cal.isDateInToday(dateAffichee) { return "Aujourd'hui" }
        if cal.isDateInYesterday(dateAffichee) { return "Hier" }
        return dateAffichee.formatted(
            Date.FormatStyle()
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .locale(localeFr)
        ).capitalized
    }

    private var totalGlucidesAffiche: Int {
        Int(repasPour(jour: dateAffichee).reduce(0.0) { $0 + $1.glucides })
    }

    private var nombreRepasAffiche: Int {
        repasPour(jour: dateAffichee).count
    }

    private var nombreSansInjection: Int {
        repasPour(jour: dateAffichee).filter { !$0.aInjection }.count
    }

    private var sousTitreRepas: String {
        let n = nombreRepasAffiche
        let sans = nombreSansInjection
        if sans == 0 {
            return "\(n) repas"
        } else if sans == 1 {
            return "\(n) repas (1 sans insuline)"
        } else {
            return "\(n) repas (\(sans) sans insuline)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            pages
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .onAppear {
            if dateScroll == nil { dateScroll = jours.last }
        }
        .onChange(of: dateScroll) { _, nouvelle in
            if let nouvelle { selectedDate = nouvelle }
            // Fermer le popup quand on change de jour.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                repasSelectionne = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: changerJour(de: -1)
            case .decrement: changerJour(de: 1)
            @unknown default: break
            }
        }
        .sheet(isPresented: $afficheInfo) {
            InfoLectureGraphe()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(libelleJour)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: libelleJour)

                chiffresCles
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    afficheInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .frame(minWidth: 44, minHeight: 28, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lecture du graphe")
                .accessibilityHint("Affiche la signification des couleurs et des icônes")

                if nombreRepasAffiche > 0 {
                    Text(sousTitreRepas)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: sousTitreRepas)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var chiffresCles: some View {
        if nombreRepasAffiche == 0 {
            Text("Aucune donnée")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tertiary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(totalGlucidesAffiche)")
                    .font(.system(size: 36, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("g")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .animation(.easeOut(duration: 0.2), value: dateAffichee)
        }
    }

    // MARK: - Pages scrollables

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
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func pagePour(jour: Date) -> some View {
        let repasJour = repasPour(jour: jour)
        if repasJour.isEmpty {
            etatVide
                .padding(.trailing, legendWidth + legendMarge)
                .padding(.leading, 16)
        } else {
            barresPour(jour: jour, repasJour: repasJour)
        }
    }

    private var etatVide: some View {
        ContentUnavailableView(
            "Aucun repas",
            systemImage: "fork.knife.circle",
            description: Text("Vos repas du jour apparaîtront ici")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Bande de légende Y fixe sur le bord droit. Chart "fantôme" partageant
    /// le même `chartYScale` que les pages, avec un fond opaque qui masque
    /// les barres qui passent en dessous pendant le scroll.
    private var legendeFixe: some View {
        Chart {
            BarMark(
                x: .value("h", Calendar.current.startOfDay(for: Date())),
                y: .value("g", maxY)
            )
            .opacity(0)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...maxY)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .stride(by: 25)) { value in
                AxisValueLabel {
                    if let g = value.as(Int.self) {
                        Text("\(g) g")
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
        .background(Color(.systemBackground))
        .allowsHitTesting(false)
    }

    // MARK: - Barres + interaction tap

    @ViewBuilder
    private func barresPour(jour: Date, repasJour: [RepasGraph]) -> some View {
        let domain = domainePour(jour: jour)

        Chart {
            ForEach(repasJour) { unRepas in
                BarMark(
                    x: .value("Heure", unRepas.heure),
                    y: .value("Glucides", unRepas.glucides),
                    width: .fixed(repasSelectionne?.id == unRepas.id ? 14 : 10)
                )
                .foregroundStyle(unRepas.verdict.couleur.gradient)
                .opacity(unRepas.aInjection ? 1.0 : 0.4)
                .cornerRadius(6)
            }

            if let selected = repasSelectionne, isSameDay(selected, jour) {
                RuleMark(x: .value("Sélection", selected.heure))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .zIndex(-1)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...maxY)
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
        .chartOverlay { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    handleTap(at: location, proxy: proxy, repasJour: repasJour)
                }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: repasSelectionne)
        .padding(.leading, 16)
        .overlay(alignment: .top) {
            if let r = repasSelectionne, isSameDay(r, jour) {
                popup(for: r, jour: jour)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity
                    ))
            }
        }
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy, repasJour: [RepasGraph]) {
        guard let date: Date = proxy.value(atX: location.x) else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                repasSelectionne = nil
            }
            return
        }
        let seuil: TimeInterval = 30 * 60
        let plusProche = repasJour.min(by: {
            abs($0.heure.timeIntervalSince(date)) < abs($1.heure.timeIntervalSince(date))
        })
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let plusProche, abs(plusProche.heure.timeIntervalSince(date)) < seuil {
                repasSelectionne = (repasSelectionne?.id == plusProche.id) ? nil : plusProche
            } else {
                repasSelectionne = nil
            }
        }
    }

    // MARK: - Popup

    @ViewBuilder
    private func popup(for r: RepasGraph, jour: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(r.emoji)
                    .font(.subheadline)
                Text(r.heure, style: .time)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(Int(r.glucides)) g")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(r.verdict.couleur)
                    .frame(width: 6, height: 6)
                Text(r.verdict.libelle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if r.aInjection {
                if let info = delaiDepuisDernierAvecInjection(r, jour: jour) {
                    Text("\(formatDuree(info.delta)) depuis \(info.heure.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Label("Sans insuline", systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }

    /// Délai entre `r` (qui DOIT avoir une injection) et le précédent repas
    /// avec injection dans la même journée, le cas échéant.
    /// Les repas sans injection ne reset pas le compteur.
    private func delaiDepuisDernierAvecInjection(_ r: RepasGraph, jour: Date) -> (heure: Date, delta: TimeInterval)? {
        let tous = repasPour(jour: jour)
        guard let idx = tous.firstIndex(where: { $0.id == r.id }) else { return nil }
        guard let dernier = tous.prefix(idx).last(where: \.aInjection) else { return nil }
        return (dernier.heure, r.heure.timeIntervalSince(dernier.heure))
    }

    private func formatDuree(_ secondes: TimeInterval) -> String {
        let total = Int(secondes)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(String(format: "%02d", m))"
    }

    private func isSameDay(_ r: RepasGraph, _ jour: Date) -> Bool {
        Calendar.current.isDate(r.heure, inSameDayAs: jour)
    }

    // MARK: - Accessibilité

    private func changerJour(de delta: Int) {
        guard let courant = dateScroll,
              let idx = jours.firstIndex(of: courant) else { return }
        let nouvelIndex = idx + delta
        guard nouvelIndex >= 0 && nouvelIndex < jours.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            dateScroll = jours[nouvelIndex]
        }
    }
}

// MARK: - Sheet « Lecture du graphe »

private struct InfoLectureGraphe: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Hauteur") {
                    Label("Quantité de glucides du repas", systemImage: "ruler")
                        .labelStyle(.titleAndIcon)
                }

                Section("Couleur") {
                    Text("Verdict glycémique post-repas, dérivé du capteur Dexcom une fois les données disponibles.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ligneVerdict(.bon)
                    ligneVerdict(.moyen)
                    ligneVerdict(.mauvais)
                    ligneVerdict(.indetermine)
                }

                Section("Insuline") {
                    Text("Une barre estompée signale un repas sans injection d'insuline enregistrée.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Tap sur une barre") {
                    Text("Affiche l'heure, la quantité de glucides, le verdict et le délai depuis le dernier repas avec injection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Lecture du graphe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func ligneVerdict(_ v: VerdictGlycemique) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(v.couleur)
                .frame(width: 12, height: 12)
                .frame(width: 24, alignment: .center)
            Text(v.libelle)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview helpers

private func _previewDate(_ h: Int, _ m: Int = 0, daysAgo: Int = 0) -> Date {
    let cal = Calendar.current
    let day = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? Date()
}

/// Mock 5 repas couvrant tous les cas de verdict + présence/absence d'injection,
/// conformément à la spec : petit-déj injecté bon, en-cas non-injecté indéterminé,
/// déjeuner injecté moyen, goûter non-injecté bon, dîner injecté mauvais.
private let _previewMockToday: [RepasGraph] = [
    RepasGraph(
        heure: _previewDate(8, 0), glucides: 54,
        aInjection: true, verdict: .bon,
        label: "Petit-déjeuner", emoji: "🥣"
    ),
    RepasGraph(
        heure: _previewDate(10, 30), glucides: 27,
        aInjection: false, verdict: .indetermine,
        label: "En-cas", emoji: "🍎"
    ),
    RepasGraph(
        heure: _previewDate(12, 30), glucides: 75,
        aInjection: true, verdict: .moyen,
        label: "Déjeuner", emoji: "🍝"
    ),
    RepasGraph(
        heure: _previewDate(16, 0), glucides: 18,
        aInjection: false, verdict: .bon,
        label: "Goûter", emoji: "🍪"
    ),
    RepasGraph(
        heure: _previewDate(20, 0), glucides: 90,
        aInjection: true, verdict: .mauvais,
        label: "Dîner", emoji: "🍕"
    ),
]

#Preview("5 repas variés (spec)") {
    @Previewable @State var date = Calendar.current.startOfDay(for: Date())
    ScrollView {
        VStack(spacing: 0) {
            GraphRepasJournee(repas: _previewMockToday, selectedDate: $date)
            Color(.systemGroupedBackground).frame(height: 600)
        }
    }
}

#Preview("État vide") {
    @Previewable @State var date = Calendar.current.startOfDay(for: Date())
    ScrollView {
        VStack(spacing: 0) {
            GraphRepasJournee(repas: [], selectedDate: $date)
            Color(.systemGroupedBackground).frame(height: 600)
        }
    }
}

#Preview("Sheet info") {
    InfoLectureGraphe()
}
