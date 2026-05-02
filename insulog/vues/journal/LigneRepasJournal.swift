//
//  LigneRepasJournal.swift
//  insulog
//
//  Created by Alexandre on 30/04/2026.
//

import SwiftUI

// MARK: - LigneRepasJournal
//
// Row d'un repas dans la liste du Journal. Deux zones horizontales :
// 1. infos texte — label + sous-ligne (heure · glucides · insuline) (flexible)
// 2. mini-courbe glycémique (largeur fixe 90pt)
//
// La row est tappable : un `NavigationLink` enveloppe l'ensemble pour
// pousser la `DetailRepasVue` au tap. La `List` parente fournit
// automatiquement le chevron de navigation à droite.
struct LigneRepasJournal: View {

    let repas: Repas
    /// Titre de la section parente ("Petit déjeuner", "Déjeuner", …) — sert
    /// de label principal de la row ET de titre de la nav bar de la page
    /// détail (le `Repas` lui-même n'embarque pas son libellé de section).
    let titreSection: String

    var body: some View {
        NavigationLink {
            DetailRepasVue(repas: repas, titreSection: titreSection)
        } label: {
            HStack(spacing: 12) {
                zoneInfos
                Spacer(minLength: 8)
                zoneCourbe
            }
            // Accessibilité : on regroupe la row pour que VoiceOver lise un seul
            // élément ("Petit déjeuner, 8h30, 45 grammes, 4 unités, réponse bonne")
            // au lieu d'énumérer les sous-vues.
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Zone 1 — Infos texte
    //
    // VStack(alignment: .leading) avec :
    // - label de la section en .body
    // - sous-ligne (.caption .secondary) heure · glucides · doses
    private var zoneInfos: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titreSection)
                .font(.body)
                .lineLimit(1)
            sousLigneInfos
        }
    }

    // Sous-ligne adaptée selon la présence d'une injection. On utilise
    // `.monospacedDigit()` pour aligner verticalement les chiffres sur
    // toutes les rows.
    @ViewBuilder
    private var sousLigneInfos: some View {
        let heure = repas.heure.formatted(date: .omitted, time: .shortened)
        let glucides = "\(repas.totalGlucides)g"

        HStack(spacing: 4) {
            Text("\(heure) · \(glucides) · ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if repas.aUneInjection {
                Text(formatInsuline(repas.totalInsuline))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("sans insuline")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
    }

    // MARK: - Zone 2 — Mini-courbe
    //
    // Cas par défaut (`etatAnalyse == nil`, ex : repas legacy) : on affiche
    // l'icône "données manquantes" plutôt qu'un état dégradé silencieux.
    private var zoneCourbe: some View {
        MiniCourbeReponse(etat: repas.etatAnalyse ?? .donneesManquantes)
    }

    // MARK: - Helpers

    /// Formate la dose d'insuline : "4u" si entier, "3.5u" sinon.
    /// On évite "4.0u" pour rester compact dans la sous-ligne.
    private func formatInsuline(_ dose: Double) -> String {
        if dose.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(dose))u"
        }
        return String(format: "%.1fu", dose)
    }
}

// MARK: - Aperçu

private func _previewHeure(_ h: Int, _ m: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
}

#Preview("Tous les états") {
    List {
        Section("Petit déjeuner") {
            LigneRepasJournal(
                repas: Repas(
                    heure: _previewHeure(8, 30),
                    aliments: [
                        Aliment(emoji: "🍞", nom: "Pain complet", quantite: 60, glucides: 30, insuline: 2),
                        Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 2),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.bon)
                ),
                titreSection: "Petit déjeuner"
            )
        }
        Section("Déjeuner") {
            LigneRepasJournal(
                repas: Repas(
                    heure: _previewHeure(12, 30),
                    aliments: [
                        Aliment(emoji: "🍝", nom: "Pâtes", quantite: 90, glucides: 60, insuline: 3.5),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.moyen)
                ),
                titreSection: "Déjeuner"
            )
            LigneRepasJournal(
                repas: Repas(
                    heure: _previewHeure(13, 0),
                    aliments: [
                        Aliment(emoji: "🍕", nom: "Pizza", quantite: 300, glucides: 90, insuline: 5),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.mauvais)
                ),
                titreSection: "Déjeuner"
            )
        }
        Section("En-cas") {
            LigneRepasJournal(
                repas: Repas(
                    heure: _previewHeure(16, 0),
                    aliments: [
                        Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.sansInjection)
                ),
                titreSection: "En-cas"
            )
            LigneRepasJournal(
                repas: Repas(
                    heure: _previewHeure(17, 30),
                    aliments: [
                        Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 1),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.enAttente)
                ),
                titreSection: "En-cas"
            )
            LigneRepasJournal(
                repas: Repas(
                    heure: _previewHeure(18, 0),
                    aliments: [
                        Aliment(emoji: "🥨", nom: "Bretzel", quantite: 50, glucides: 30, insuline: 1.5),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.donneesManquantes)
                ),
                titreSection: "En-cas"
            )
        }
    }
    .listStyle(.insetGrouped)
}
