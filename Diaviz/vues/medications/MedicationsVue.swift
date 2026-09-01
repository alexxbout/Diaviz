//
//  MedicationsVue.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI
import SwiftData

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

    /// Contexte du hub SwiftData — passé au service au démarrage de la vue.
    @Environment(\.modelContext) private var modelContext

    @State private var service = InjectionsService()

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

    /// Dose de la **dernière injection lente** enregistrée (toutes dates
    /// confondues) — sert à préremplir la sheet lente avec la dose
    /// habituelle plutôt qu'une valeur fixe. `nil` si aucun historique.
    private var derniereDoseLente: Double? {
        service.injections
            .filter { $0.type == .lente }
            .max { $0.heure < $1.heure }?
            .dose
    }

    /// Zone de la dernière injection rapide (toutes injections rapides
    /// confondues, lente exclue) — sert au `SiteInjectionPicker` pour le
    /// warning de rotation des sites.
    /// Zone de la dernière injection rapide, en **excluant** l'injection en
    /// cours d'édition (sinon elle se comparerait à elle-même et déclencherait
    /// un faux warning de rotation des sites).
    private func derniereZoneRapide(excluant id: UUID? = nil) -> ZoneInjection? {
        derniereZone(excluant: id) { $0.type != .lente }
    }

    private func derniereZoneLente(excluant id: UUID? = nil) -> ZoneInjection? {
        derniereZone(excluant: id) { $0.type == .lente }
    }

    private func derniereZone(excluant id: UUID?, filtre: (Injection) -> Bool) -> ZoneInjection? {
        service.injections
            .lazy
            .filter { $0.id != id }
            .filter(filtre)
            .max(by: { $0.heure < $1.heure })?
            .zoneInjection
    }

    /// État de la carte lente — calculé depuis le service et l'horloge.
    ///
    /// L'heure « habituelle » est **adaptative** : dérivée de la dernière
    /// dose de lente enregistrée + l'intervalle minimum du profil, plutôt
    /// qu'une heure fixe chaque jour (`InjectionsService.prochaineLenteAttendue`).
    /// Tant qu'aucune lente n'a jamais été enregistrée, on retombe sur 22h
    /// comme amorce — il n'y a pas encore de dose dont dériver l'ancrage.
    private var etatCarteLente: CarteInsulineLente.Etat {
        if let lente = lenteDuJour {
            return .enregistree(lente)
        }
        let intervalle = ProfilService.shared.profil.intervalleMinimumLenteEffectif
        let dateHabituelle = service.prochaineLenteAttendue(intervalleHeures: intervalle)
            ?? HeureDuJour(heure: 22, minute: 0).date(pour: selectedDate)
        let estAujourdhui = Calendar.current.isDateInToday(selectedDate)
        if estAujourdhui && Date.now > dateHabituelle {
            return .aPrendre(heureHabituelle: dateHabituelle)
        }
        return .prochainePrevue(heureHabituelle: dateHabituelle)
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
        // Titres de section en clair et non en petites capitales, et 24pt
        // entre les groupes : même rythme que les pages d'analyse, sans
        // renoncer à la `List` (séparateurs, swipe, cellules natives).
        .listSectionSpacing(24)
        .navigationTitle("Médications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { menuAjouter }
        .sheet(item: $sheetActive) { sheet in
            sheetVue(pour: sheet)
        }
        .task { service.demarrer(contexte: modelContext) }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var menuAjouter: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    sheetActive = .correction
                } label: {
                    Label("Insuline rapide", systemImage: "drop.fill")
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
        } header: {
            TitreSectionListe(texte: "La journée")
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
                    switch etatCarteLente {
                    case .aPrendre:
                        sheetActive = .lente
                    case .enregistree(let lente):
                        sheetActive = .editionLente(lente)
                    case .prochainePrevue:
                        break
                    }
                }
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            TitreSectionListe(texte: "Insuline lente")
        }
    }

    private var sectionCorrections: some View {
        Section {
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
                    onTap: { sheetActive = .editionCorrection($0) },
                    onSupprimer: { service.supprimer($0) }
                )
            }
        } header: {
            TitreSectionListe(texte: "Corrections")
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
                TitreSectionListe(texte: "Bolus repas")
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
                derniereZoneLente: derniereZoneLente(),
                doseParDefaut: derniereDoseLente,
                nomMedicamentParDefaut: ProfilService.shared.profil.insulineLente.rawValue,
                onValider: { service.enregistrer($0) }
            )
        case .correction:
            SheetCorrection(
                derniereZoneRapide: derniereZoneRapide(),
                onValider: { service.enregistrer($0) }
            )
        case .editionLente(let inj):
            SheetInsulineLente(
                injectionExistante: inj,
                derniereZoneLente: derniereZoneLente(excluant: inj.id),
                onValider: { service.enregistrer($0) }
            )
        case .editionCorrection(let inj):
            SheetCorrection(
                injectionExistante: inj,
                derniereZoneRapide: derniereZoneRapide(excluant: inj.id),
                onValider: { service.enregistrer($0) }
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

#if DEBUG
#Preview {
    NavigationStack {
        MedicationsVue()
    }
    .modelContainer(InjectionsService.conteneurApercu)
}
#endif
