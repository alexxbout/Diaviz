//
//  SheetEditionActiviteHealthKit.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

/// Sheet d'édition allégée pour une activité importée depuis Apple Santé.
///
/// Contrairement à `SheetNouvelleActivite` qui sert à la fois pour la
/// création et l'édition d'activités manuelles, cette sheet n'expose
/// **que** les champs subjectifs — ceux que l'utilisateur peut
/// légitimement renseigner ou ajuster sans entrer en conflit avec la
/// donnée source côté HealthKit.
///
/// Champs **éditables** : `glucidesPreSport`, `intensite`, `note`.
/// Champs **lecture seule** : type, date de début, durée, FC, calories,
/// distance — affichés en `Form` avec une mention discrète « Apple Santé ».
struct SheetEditionActiviteHealthKit: View {

    // MARK: - Paramètres

    /// L'activité à éditer. Doit avoir `source == .healthKit` — assertion
    /// laissée à la responsabilité de l'appelant (la sheet n'a pas de
    /// branche pour `.manuel`, qui passerait par `SheetNouvelleActivite`).
    let activite: ActiviteSportive
    let onValider: (ActiviteSportive) -> Void

    // MARK: - Init

    init(activite: ActiviteSportive, onValider: @escaping (ActiviteSportive) -> Void) {
        self.activite = activite
        self.onValider = onValider
        _intensite = State(initialValue: activite.intensite)
        _glucidesTexte = State(
            initialValue: activite.glucidesPreSport.map { String(format: "%g", $0) } ?? ""
        )
        _note = State(initialValue: activite.note ?? "")
    }

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local éditable

    @State private var intensite: IntensiteSport
    @State private var glucidesTexte: String
    @State private var note: String

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            Form {
                bandeauSource
                sectionDonneesObjectives
                sectionIntensite
                sectionGlucides
                sectionNote
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { confirmer() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    // MARK: - Bandeau source
    //
    // Note explicative en tête de sheet : explique pourquoi certains
    // champs sont en lecture seule. Discrète (caption + icône info)
    // mais visible immédiatement à l'ouverture pour éviter la frustration
    // « pourquoi je ne peux pas changer la durée ? ».

    private var bandeauSource: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Cette activité provient d'Apple Santé. Les données objectives ne peuvent pas être modifiées.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Données objectives (lecture seule)
    //
    // `Form` row classique : libellé à gauche, valeur à droite en
    // `.secondary` pour signaler immédiatement la nature non-éditable.
    // Même structure que les sections « Métriques » de la page détail
    // pour une cohérence visuelle entre les deux écrans.

    private var sectionDonneesObjectives: some View {
        Section {
            HStack {
                Text("Type")
                    .foregroundStyle(.primary)
                Spacer()
                Label(activite.type.rawValue, systemImage: activite.type.icone)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Type : \(activite.type.rawValue)")
            ligneDonnee("Heure de début", valeur: heureFormatee)
            ligneDonnee("Durée", valeur: dureeFormatee)
            if let fc = activite.healthKitData?.fcMoyenne {
                ligneDonnee("FC moyenne", valeur: "\(Int(fc)) bpm")
            }
            if let cal = activite.healthKitData?.caloriesActives {
                ligneDonnee("Calories", valeur: "\(Int(cal)) kcal")
            }
            if let dist = activite.healthKitData?.distanceMetres {
                ligneDonnee("Distance", valeur: distanceFormatee(dist))
            }
        } header: {
            Text("Données Apple Santé")
        }
    }

    @ViewBuilder
    private func ligneDonnee(_ libelle: String, valeur: String) -> some View {
        HStack {
            Text(libelle)
                .foregroundStyle(.primary)
            Spacer()
            Text(valeur)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(libelle) : \(valeur)")
    }

    // MARK: - Intensité (éditable)

    private var sectionIntensite: some View {
        Section("Intensité") {
            Picker("Intensité", selection: $intensite) {
                ForEach(IntensiteSport.allCases, id: \.self) { niveau in
                    Text(niveau.rawValue).tag(niveau)
                }
            }
            .pickerStyle(.segmented)
            Text(intensite.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Glucides pré-sport (éditable)

    private var sectionGlucides: some View {
        Section {
            HStack {
                TextField("Optionnel", text: $glucidesTexte)
                    .keyboardType(.decimalPad)
                Text("g")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Glucides pré-sport")
        } footer: {
            Text("À renseigner si vous avez pris des glucides juste avant l'activité.")
        }
    }

    // MARK: - Note (éditable)

    private var sectionNote: some View {
        Section("Note") {
            TextField("Ajouter une note...", text: $note, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    // MARK: - Helpers de formatage

    /// Date affichée en lecture seule en haut de la section « Données
    /// Apple Santé » — locale `fr_FR` forcée pour rester cohérent avec
    /// l'en-tête de la `DetailActiviteVue`.
    private var heureFormatee: String {
        Self.formatterDateHeure
            .string(from: activite.dateDebut)
            .capitalizedFirstLetter
    }

    private static let formatterDateHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        // « jeu. 30 avr. à 18h45 » — abrégé pour tenir dans une row.
        f.dateFormat = "EEE d MMM 'à' H'h'mm"
        return f
    }()

    private var dureeFormatee: String {
        let m = activite.dureeMinutes
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h\(r)"
    }

    /// `7200m` → `"7,2 km"` ; `< 1000m` → `"800 m"`. Conversion explicite
    /// pour ne pas dépendre du formattage Measurement (qui imposerait un
    /// affichage anglo-saxon par défaut sans configuration locale).
    private func distanceFormatee(_ metres: Double) -> String {
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000)
                .replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(metres)) m"
    }

    // MARK: - Actions

    private var glucidesDouble: Double? {
        let trim = glucidesTexte
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return trim.isEmpty ? nil : Double(trim)
    }

    /// Reconstruit une `ActiviteSportive` en réutilisant tous les champs
    /// objectifs intacts — seuls les trois champs éditables changent.
    private func confirmer() {
        let nouvelle = ActiviteSportive(
            id: activite.id,
            type: activite.type,
            dateDebut: activite.dateDebut,
            dureeMinutes: activite.dureeMinutes,
            intensite: intensite,
            glucidesPreSport: glucidesDouble,
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
            source: activite.source,
            healthKitData: activite.healthKitData
        )
        onValider(nouvelle)
        dismiss()
    }
}

// MARK: - String helper
//
// Capitalise uniquement la première lettre (« jeu. 30 avr. » → « Jeu.
// 30 avr. »). Dupliqué dans chaque fichier qui en a besoin pour
// garder l'indépendance des modules.
private extension String {
    var capitalizedFirstLetter: String {
        guard let premiere = first else { return self }
        return String(premiere).uppercased() + dropFirst()
    }
}

// MARK: - Aperçu

#Preview("Édition HealthKit") {
    SheetEditionActiviteHealthKit(
        activite: ActiviteSportive(
            type: .course,
            dateDebut: Date(),
            dureeMinutes: 45,
            intensite: .moderee,
            glucidesPreSport: 15,
            note: "Footing au parc",
            source: .healthKit,
            healthKitData: HealthKitWorkoutData(
                workoutUUID: UUID(),
                fcMoyenne: 145,
                fcMax: 168,
                caloriesActives: 420,
                distanceMetres: 7200,
                sourceAppareil: "Apple Watch Series 9"
            )
        ),
        onValider: { _ in }
    )
}

#Preview("Édition HealthKit — minimal") {
    SheetEditionActiviteHealthKit(
        activite: ActiviteSportive(
            type: .yoga,
            dateDebut: Date(),
            dureeMinutes: 30,
            intensite: .faible,
            source: .healthKit,
            healthKitData: HealthKitWorkoutData(
                workoutUUID: UUID(),
                fcMoyenne: 95,
                fcMax: 112,
                caloriesActives: 110,
                distanceMetres: nil,
                sourceAppareil: "Apple Watch Series 9"
            )
        ),
        onValider: { _ in }
    )
}
