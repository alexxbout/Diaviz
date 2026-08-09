//
//  CarteWorkoutImport.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

// MARK: - EtatSelectionWorkout
//
// Tuple structuré qui agrège les deux axes que la carte doit faire
// remonter au parent (sheet) :
// - sélectionnée ou pas (drive le compteur du bouton « Importer »)
// - intensité ressentie (pré-remplie depuis la FC, ajustable)
//
// On le passe en `@Binding` à la carte plutôt qu'en `@State` interne
// parce que le parent a besoin de la liste complète pour soumettre
// l'import.
struct EtatSelectionWorkout: Hashable {
    var selectionnee: Bool = false
    var intensite: IntensiteSport
}

/// Carte d'un workout HealthKit en attente d'import. Deux états visuels
/// commutables au tap :
///
/// - **Compacte** (non sélectionnée) : cercle vide + emoji + titre +
///   métriques d'une ligne. Largeur entière, padding 16pt.
/// - **Étendue** (sélectionnée) : checkmark coloré + métriques + radios
///   d'intensité.
///
/// Fond `systemBackground` (blanc en mode clair, noir en mode sombre)
/// pour ressortir nettement du `systemGroupedBackground` de la sheet.
///
/// L'animation de transition est un `.spring(response: 0.4,
/// dampingFraction: 0.85)` cohérent avec le reste de l'app (cf.
/// `SheetNouvelleActivite`).
struct CarteWorkoutImport: View {

    let workout: WorkoutHealthKitCandidat

    /// État de sélection — propriété du parent pour permettre au
    /// bouton « Importer » de connaître la liste complète des choix.
    @Binding var etat: EtatSelectionWorkout

    // MARK: - Corps

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            zoneEnTete
            if etat.selectionnee {
                zoneEnrichissement
            }
        }
        .padding(16)
        .surfaceCarte(fond: Color(.systemBackground))
        .overlay(
            NiveauCarte.carte.forme
                .strokeBorder(
                    etat.selectionnee ? Color.accentColor : .clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { basculerSelection() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(etat.selectionnee ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - En-tête (toujours visible)
    //
    // Cercle de sélection à gauche + bloc d'infos à droite. Le cercle
    // change d'apparence selon `etat.selectionnee` : vide bordé en
    // mode compact, plein avec checkmark blanc en mode étendu.

    private var zoneEnTete: some View {
        HStack(alignment: .top, spacing: 12) {
            cercleSelection

            VStack(alignment: .leading, spacing: 4) {
                titreSport
                ligneHoraire
                ligneMetriques
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cercleSelection: some View {
        if etat.selectionnee {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
        } else {
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }

    private var titreSport: some View {
        Label(workout.typeSport.rawValue, systemImage: workout.typeSport.icone)
            .font(.body.bold())
            .lineLimit(1)
    }

    /// Sous-ligne « Aujourd'hui · 07:15 · 45min » — date relative,
    /// heure courte locale, durée formattée. La date est en tête parce
    /// qu'elle change la lecture de l'heure (07:15 hier ≠ 07:15
    /// aujourd'hui pour un import). `monospacedDigit` pour aligner les
    /// chiffres entre rows successives.
    private var ligneHoraire: some View {
        let date = formaterDate(workout.dateDebut)
        let heure = workout.dateDebut.formatted(date: .omitted, time: .shortened)
        let duree = formaterDuree(workout.dureeMinutes)
        return Text("\(date) · \(heure) · \(duree)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    /// Sous-ligne métriques HealthKit — uniquement les champs
    /// disponibles. On ne montre pas un trou « FC moy — » qui suggérerait
    /// que la donnée est censée être là.
    @ViewBuilder
    private var ligneMetriques: some View {
        let parts = metriquesAffichables
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var metriquesAffichables: [String] {
        var parts: [String] = []
        if let fc = workout.fcMoyenne {
            parts.append("FC moy \(Int(fc.rounded()))")
        }
        if let kcal = workout.caloriesActives {
            parts.append("\(Int(kcal.rounded())) kcal")
        }
        if let m = workout.distanceMetres {
            parts.append(formaterDistance(m))
        }
        return parts
    }

    // MARK: - Zone d'enrichissement (visible si sélectionnée)
    //
    // Divider fin pour démarquer du bloc d'en-tête, puis la section
    // intensité.

    private var zoneEnrichissement: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.top, 12)

            sectionIntensite
        }
    }

    private var sectionIntensite: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Intensité")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(IntensiteSport.allCases, id: \.self) { niveau in
                    BoutonRadioIntensite(
                        intensite: niveau,
                        selectionnee: etat.intensite == niveau
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            etat.intensite = niveau
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func basculerSelection() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            etat.selectionnee.toggle()
        }
    }

    // MARK: - Helpers de formatage

    /// Date relative en tête de la sous-ligne horaire :
    /// « Aujourd'hui » / « Hier » / sinon « Mercredi 12 mars » au
    /// format long français. On évite le format numérique « 12/03 »
    /// qui se lit moins vite et qui est ambigu avec l'usage US.
    private func formaterDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Aujourd'hui" }
        if cal.isDateInYesterday(date) { return "Hier" }
        return date.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .locale(Locale(identifier: "fr_FR"))
        )
    }

    private func formaterDuree(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    /// `7200m` → `7,2 km` ; `850m` → `850 m`. Au-delà du km, deux
    /// décimales seraient artificiellement précises pour un capteur
    /// montre.
    private func formaterDistance(_ metres: Double) -> String {
        if metres >= 1000 {
            let km = metres / 1000
            return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(metres.rounded())) m"
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Non sélectionnée") {
    StatefulPreviewWrapper(
        EtatSelectionWorkout(intensite: .moderee)
    ) { etat in
        CarteWorkoutImport(workout: .mockCourse, etat: etat)
            .padding()
    }
}

#Preview("Sélectionnée") {
    StatefulPreviewWrapper(
        EtatSelectionWorkout(selectionnee: true, intensite: .intense)
    ) { etat in
        CarteWorkoutImport(workout: .mockCourse, etat: etat)
            .padding()
    }
}
#endif

// MARK: - Helper de preview
//
// SwiftUI ne fournit pas nativement de wrapper d'état pour previews
// — sans ça, on ne pourrait pas exposer un binding qui évolue (radios
// d'intensité). Petit utilitaire local au fichier puisqu'il n'a
// d'usage qu'ici.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
