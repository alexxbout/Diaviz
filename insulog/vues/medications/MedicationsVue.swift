//
//  MedicationsVue.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Page racine « Médications ». Pushée depuis `JournalVue` via un
/// `NavigationLink`, donc PAS de `NavigationStack` propre — elle
/// hérite de la stack du parent.
///
/// Composition en sections d'une même `List.insetGrouped` :
/// - Section graphe — timeline 24h paginée jour par jour
/// - Section carte lente — état de l'insuline lente du jour
/// - Section corrections — rows tappables (édition)
/// - Section bolus repas — lecture seule
struct MedicationsVue: View {

    // MARK: - État

    @State private var service = InjectionsServiceMock.shared

    /// Date affichée — utilisée pour filtrer les sections en dessous.
    /// Représente le début de la journée (00:00 local).
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Sheet active (ajout ou édition).
    @State private var sheetActive: SheetMedication?

    // MARK: - Calculs dérivés

    private var injectionsDuJour: [Injection] {
        service.injectionsDuJour(selectedDate)
    }

    private var corrections: [Injection] {
        injectionsDuJour.filter { $0.type == .rapideCorrection }
    }

    private var bolusRepas: [Injection] {
        injectionsDuJour.filter { $0.type == .rapideRepas }
    }

    private var lenteDuJour: Injection? {
        service.lenteDuJour(selectedDate)
    }

    /// Zone de la dernière injection rapide (toutes injections rapides
    /// confondues, lente exclue) — sert au `SiteInjectionPicker` pour le
    /// warning de rotation des sites.
    private var derniereZoneRapide: ZoneInjection? {
        derniereZone { $0.type != .lente }
    }

    private var derniereZoneLente: ZoneInjection? {
        derniereZone { $0.type == .lente }
    }

    private func derniereZone(filtre: (Injection) -> Bool) -> ZoneInjection? {
        service.injections
            .lazy
            .filter(filtre)
            .max(by: { $0.heure < $1.heure })?
            .zoneInjection
    }

    /// État de la carte lente — calculé depuis le service et l'horloge.
    private var etatCarteLente: CarteInsulineLente.Etat {
        if let lente = lenteDuJour {
            return .enregistree(lente)
        }
        let heureHabit = service.heureHabituelleLente
        let dateHabituelle = heureHabit.date(pour: selectedDate)
        let estAujourdhui = Calendar.current.isDateInToday(selectedDate)
        if estAujourdhui && Date.now > dateHabituelle {
            return .aPrendre(heureHabituelle: heureHabit)
        }
        return .prochainePrevue(heureHabituelle: heureHabit)
    }

    /// La carte lente n'est rendue que si elle apporte de l'info :
    /// aujourd'hui (toujours utile), ou un jour passé avec une lente
    /// effectivement enregistrée.
    private var carteLenteVisible: Bool {
        if Calendar.current.isDateInToday(selectedDate) { return true }
        return lenteDuJour != nil
    }

    // MARK: - Corps

    var body: some View {
        List {
            sectionGraphe
            if carteLenteVisible {
                sectionCarteLente
            }
            sectionCorrections
            if !bolusRepas.isEmpty {
                sectionBolusRepas
            }
        }
        .listStyle(.insetGrouped)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Médications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { menuAjouter }
        .sheet(item: $sheetActive) { sheet in
            sheetVue(pour: sheet)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var menuAjouter: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    sheetActive = .correction
                } label: {
                    Label("Correction rapide", systemImage: "drop.fill")
                }
                Button {
                    sheetActive = .lente
                } label: {
                    Label("Insuline lente", systemImage: "drop.fill")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
            }
            .accessibilityLabel("Ajouter une médication")
        }
    }

    // MARK: - Sections

    /// Section graphe — la row spanne toute la cellule (sans insets) et
    /// utilise un fond transparent : le graphe apporte sa propre carte
    /// englobante (RoundedRectangle + `secondarySystemGroupedBackground`).
    private var sectionGraphe: some View {
        Section {
            GrapheJourneeMedications(
                injections: service.injections,
                selectedDate: $selectedDate
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// Section carte lente — la carte fournit son propre fond + bordure
    /// et remplit la cellule (marges horizontales du `.insetGrouped`
    /// natif uniquement).
    private var sectionCarteLente: some View {
        Section {
            CarteInsulineLente(
                etat: etatCarteLente,
                onTap: {
                    if case .aPrendre = etatCarteLente {
                        sheetActive = .lente
                    }
                }
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var sectionCorrections: some View {
        Section("Corrections") {
            if corrections.isEmpty {
                Text("Aucune correction aujourd'hui")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
            } else {
                ListeCorrections(
                    corrections: corrections,
                    onTap: { sheetActive = .editionCorrection($0) }
                )
            }
        }
    }

    /// Section bolus repas — uniquement rendue si non vide. Header
    /// custom avec sous-titre « Saisis via la page Repas ». Le
    /// `.textCase(nil)` désactive la mise en majuscules auto des
    /// headers en `.insetGrouped`.
    private var sectionBolusRepas: some View {
        Section {
            ListeBolusRepas(bolus: bolusRepas)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bolus repas")
                Text("Saisis via la page Repas")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .textCase(nil)
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetVue(pour sheet: SheetMedication) -> some View {
        switch sheet {
        case .lente:
            SheetInsulineLente(
                derniereZoneLente: derniereZoneLente,
                onValider: { service.ajouter($0) }
            )
        case .correction:
            SheetCorrection(
                derniereZoneRapide: derniereZoneRapide,
                onValider: { service.ajouter($0) }
            )
        case .editionLente(let inj):
            SheetInsulineLente(
                injectionExistante: inj,
                derniereZoneLente: derniereZoneLente,
                onValider: { service.ajouter($0) }
            )
        case .editionCorrection(let inj):
            SheetCorrection(
                injectionExistante: inj,
                derniereZoneRapide: derniereZoneRapide,
                onValider: { service.ajouter($0) }
            )
        }
    }
}

// MARK: - Routage de la sheet

/// Discrimine les sheets routées par un seul `.sheet(item:)` au niveau
/// de la racine du body, pour éviter les conflits de présentation.
private enum SheetMedication: Identifiable {
    case lente
    case correction
    case editionLente(Injection)
    case editionCorrection(Injection)

    var id: String {
        switch self {
        case .lente:                    return "lente"
        case .correction:               return "correction"
        case .editionLente(let i):      return "edition-lente-\(i.id.uuidString)"
        case .editionCorrection(let i): return "edition-correction-\(i.id.uuidString)"
        }
    }
}

// MARK: - Aperçu

#Preview {
    NavigationStack {
        MedicationsVue()
    }
}
