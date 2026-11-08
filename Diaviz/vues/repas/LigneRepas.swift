//
//  LigneRepas.swift
//  diaviz
//
//  Created by Alexandre on 30/04/2026.
//

import SwiftUI

// MARK: - LigneRepas
//
// Row d'un repas dans la liste du Journal. Deux zones horizontales :
// 1. infos texte — label + sous-ligne (heure · glucides · insuline) (flexible)
// 2. mini-courbe glycémique (largeur fixe 90pt)
//
// La row est tappable : un `NavigationLink` enveloppe l'ensemble pour
// pousser la `DetailRepasVue` au tap. La `List` parente fournit
// automatiquement le chevron de navigation à droite.
struct LigneRepas: View {

    /// Service hub partagé — utilisé pour brancher la suppression depuis la
    /// page détail sur le vrai store.
    @Environment(RepasService.self) private var repasService

    let repas: Repas
    /// Titre de la section parente ("Petit déjeuner", "Déjeuner", …) — sert
    /// de label principal de la row ET de titre de la nav bar de la page
    /// détail (le `Repas` lui-même n'embarque pas son libellé de section).
    let titreSection: String

    var body: some View {
        if repas.estEncoreDansLeHub {
            contenu
        }
    }

    private var contenu: some View {
        NavigationLink {
            DetailRepasVue(
                repas: repas,
                titreSection: titreSection,
                onSupprimer: { repasService.supprimer(repas) }
            )
        } label: {
            // Row volontairement compacte : la ventilation des doses, les
            // motifs d'ajustement et le contexte partent dans des rows sœurs
            // (`RecapDosesRepas`). Les empiler ici allongeait la row tappable,
            // ce qui éloignait le chevron du `NavigationLink` (centré sur
            // toute la hauteur) et faisait passer la mini-courbe au second
            // plan derrière un bloc pleine largeur.
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
    // - label de la section, en `headline` : c'est l'en-tête du repas, il doit
    //   se distinguer des rows d'aliments qui le suivent dans la même section
    //   (avant, les deux étaient en `.body` — d'où l'absence de hiérarchie).
    // - sous-ligne (.caption .secondary) heure · glucides · dose
    private var zoneInfos: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titreSection)
                .font(.headline)
                .lineLimit(1)
            sousLigneInfos
            badgeContexte
        }
    }

    /// Contexte libre en badge, juste sous le titre et la sous-ligne : il
    /// qualifie le repas lui-même (« je prends la voiture »), pas ses doses —
    /// sa place est dans l'identité du repas, pas dans le récap d'insuline.
    ///
    /// Le normalisé prime sur le brut quand la résolution en tâche de fond a
    /// abouti (`ReferentielContextesService`), sinon on affiche la saisie
    /// telle quelle.
    @ViewBuilder
    private var badgeContexte: some View {
        let evenements = repas.evenementsAffiches
        if !evenements.isEmpty {
            RangeeBadges(items: evenements.map { ItemBadge($0.affichageResolu, couleur: .purple) })
                .padding(.top, 4)
        }
    }

    // Sous-ligne adaptée selon la présence d'une injection. On utilise
    // `.monospacedDigit()` pour aligner verticalement les chiffres sur
    // toutes les rows.
    //
    // La dose n'y figure que sur un repas **sans** correction : dès qu'il y en
    // a une, la ventilation part dans `RecapDosesRepas` et la répéter ici
    // serait ambigu (laquelle des deux ?). Même condition que
    // `RecapDosesRepas.afficheVentilation`.
    private var doseVentileeAilleurs: Bool {
        RecapDosesRepas.aUneVentilation(repas)
    }

    @ViewBuilder
    private var sousLigneInfos: some View {
        let heure = repas.heure.formatted(date: .omitted, time: .shortened)
        let glucides = "\(repas.totalGlucides)g"

        HStack(spacing: 4) {
            Text(doseVentileeAilleurs ? "\(heure) · \(glucides)" : "\(heure) · \(glucides) · ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if !doseVentileeAilleurs {
                if repas.aUneInjection {
                    Text(repas.totalInsuline.doseInsulineFormatee)
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
    }

    // MARK: - Zone 2 — Mini-courbe
    //
    // Cas par défaut (`etatAnalyse == nil`, ex : repas legacy) : on affiche
    // l'icône "données manquantes" plutôt qu'un état dégradé silencieux.
    private var zoneCourbe: some View {
        MiniCourbeReponse(etat: repas.etatAnalyse ?? .donneesManquantes)
    }

}

// MARK: - Aperçu

private func _previewHeure(_ h: Int, _ m: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
}

#if DEBUG
#Preview("Tous les états") {
    List {
        Section("Petit déjeuner") {
            LigneRepas(
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
            LigneRepas(
                repas: Repas(
                    heure: _previewHeure(12, 30),
                    aliments: [
                        Aliment(emoji: "🍝", nom: "Pâtes", quantite: 90, glucides: 60, insuline: 3.5),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.moyen)
                ),
                titreSection: "Déjeuner"
            )
            LigneRepas(
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
            LigneRepas(
                repas: Repas(
                    heure: _previewHeure(16, 0),
                    aliments: [
                        Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.sansInjection)
                ),
                titreSection: "En-cas"
            )
            LigneRepas(
                repas: Repas(
                    heure: _previewHeure(17, 30),
                    aliments: [
                        Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 1),
                    ],
                    etatAnalyse: ReponseGlycemiqueServiceMock.cas(.enAttente)
                ),
                titreSection: "En-cas"
            )
            LigneRepas(
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
    .environment(RepasService.apercu())
}
#endif
