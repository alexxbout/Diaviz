//
//  LigneActiviteSport.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

// MARK: - LigneActiviteSport
//
// Row d'une activité sportive dans la liste de la page Sport. Deux
// zones horizontales — pattern identique à la `LigneRepas` :
// 1. infos texte — type avec emoji + sous-ligne (heure · durée · intensité)
// 2. mini-courbe glycémique pendant la session (largeur fixe 90pt)
//
// La row est tappable : un `NavigationLink` enveloppe l'ensemble pour
// pousser la `DetailActiviteVue`. Le swipe gauche reste géré par le
// parent (`.swipeActions` côté `ListeActivitesSport`).
struct LigneActiviteSport: View {

    let activite: ActiviteSportive

    /// État de la mini-courbe — calculé par le parent depuis le service
    /// (réponse pré-calculée si disponible, sinon `.donneesManquantes`).
    let etatCourbe: EtatMiniCourbeSport

    /// Persiste une activité éditée depuis la page détail (upsert hub).
    /// Optionnel : les previews qui n'ouvrent pas le détail peuvent l'omettre.
    var onEnregistrer: ((ActiviteSportive) -> Void)? = nil

    /// Supprime cette activité depuis la page détail. Optionnel pour la
    /// même raison.
    var onSupprimer: (() -> Void)? = nil

    /// Corrections et resucrages corrélés à cette activité — dérivés par le
    /// parent depuis le service, transmis à la page détail.
    var evenements: [EvenementActivite] = []

    var body: some View {
        NavigationLink {
            DetailActiviteVue(
                activite: activite,
                reponse: reponseDepuisEtat,
                minutesAttenteRestantes: minutesAttenteDepuisEtat,
                onEnregistrer: onEnregistrer,
                onSupprimer: onSupprimer,
                evenements: evenements
            )
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    zoneInfos
                    Spacer(minLength: 8)
                    zoneCourbe
                }
                RangeeBadges(items: badges)
            }
            // Accessibilité : on regroupe la row pour que VoiceOver lise un
            // seul élément ("Course, 7h15, 45 minutes, modérée, glycémie
            // stable") au lieu d'énumérer les sous-vues.
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Badges
    //
    // Même châssis que `LigneRepas` (en-tête + mini-courbe + rangée de
    // badges), en plus léger : pas de bloc doses ni de rows d'aliments, une
    // séance n'a pas de ventilation d'insuline à montrer.
    //
    // Les glucides pré-sport et la source HealthKit passent ici plutôt que
    // d'être noyés dans la sous-ligne texte / un footer dédié : un badge se
    // repère au coup d'œil, et la sous-ligne ne tronque plus face à la
    // mini-courbe dès que les deux étaient présents.
    private var badges: [ItemBadge] {
        var items: [ItemBadge] = []
        let glucides = activite.glucidesPreSportTotal
        if glucides > 0 {
            items.append(ItemBadge("+\(formate(glucides))g pré-sport", couleur: .green))
        }
        if activite.source == .healthKit {
            items.append(ItemBadge("Apple Santé", couleur: .pink, systemImage: "heart"))
        }
        return items
    }

    // MARK: - Extraction depuis l'état de la mini-courbe
    //
    // La page détail attend une `ReponseGlycemiqueSport?` + un délai
    // optionnel — alors que la row ne connaît qu'un `EtatMiniCourbeSport`.
    // On déballe ici pour ne pas faire transiter l'enum jusqu'au détail
    // (qui aurait alors deux représentations parallèles du même état).

    private var reponseDepuisEtat: ReponseGlycemiqueSport? {
        if case .disponible(let r) = etatCourbe { return r }
        return nil
    }

    private var minutesAttenteDepuisEtat: Int? {
        if case .enAttente(let m) = etatCourbe { return m }
        return nil
    }

    // MARK: - Zone 1 — Infos texte
    //
    // VStack(alignment: .leading) avec :
    // - label avec emoji intégré en .body
    // - sous-ligne (.caption .secondary) heure · durée · intensité
    //
    // Les glucides pré-sport et la source HealthKit sont passés en badges
    // (voir `badges`) — plus lisibles là qu'en suffixe de sous-ligne et en
    // footer séparé.
    private var zoneInfos: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(activite.type.rawValue, systemImage: activite.type.icone)
                .font(.headline)
                .lineLimit(1)
            sousLigneInfos
        }
    }

    @ViewBuilder
    private var sousLigneInfos: some View {
        let heure = activite.dateDebut.formatted(date: .omitted, time: .shortened)
        let duree = formaterDuree(activite.dureeMinutes)

        // `.monospacedDigit()` aligne verticalement les chiffres entre
        // les rows quand plusieurs activités sont empilées.
        Text(sousLigneTexte(heure: heure, duree: duree))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    /// Construit la sous-ligne en une seule passe — préférable à des
    /// `Text` concaténés en HStack, qui interdiraient le `.lineLimit(1)`
    /// avec troncature propre.
    private func sousLigneTexte(heure: String, duree: String) -> String {
        [heure, duree, activite.intensite.rawValue].joined(separator: " · ")
    }

    // MARK: - Zone 2 — Mini-courbe
    private var zoneCourbe: some View {
        MiniCourbeSport(etat: etatCourbe, dureeMinutes: activite.dureeMinutes)
    }

    // MARK: - Helpers

    /// Formate une durée en minutes : "45min" si < 60min, sinon "1h15"
    /// (style cohérent avec l'heure du jour dans l'en-tête du graphe).
    private func formaterDuree(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    /// Formate un Double : "15" si entier, "15.5" sinon. Évite le "15.0g"
    /// qui semble artificiellement précis.
    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Toutes les variantes") {
    let service = ActivitesSportService.apercu()

    return List {
        Section("Aujourd'hui") {
            ForEach(service.activitesDuJour(Date())) { activite in
                LigneActiviteSport(
                    activite: activite,
                    etatCourbe: service.reponse(pour: activite)
                        .map { .disponible($0) } ?? .donneesManquantes
                )
            }
        }
        Section("États dégradés") {
            LigneActiviteSport(
                activite: ActiviteSportive(
                    type: .course,
                    dateDebut: Date(),
                    dureeMinutes: 30,
                    intensite: .moderee
                ),
                etatCourbe: .enAttente(minutesRestantes: 90)
            )
            LigneActiviteSport(
                activite: ActiviteSportive(
                    type: .musculation,
                    dateDebut: Date(),
                    dureeMinutes: 45,
                    intensite: .intense
                ),
                etatCourbe: .donneesManquantes
            )
        }
        Section("Importée depuis Apple Santé") {
            // Active le rendu du footer `.source == .healthKit` —
            // sert de garde-fou visuel pour s'assurer que la ligne
            // grandit proprement avec la nouvelle métadonnée.
            LigneActiviteSport(
                activite: ActiviteSportive(
                    type: .course,
                    dateDebut: Date(),
                    dureeMinutes: 45,
                    intensite: .moderee,
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
                etatCourbe: .donneesManquantes
            )
        }
    }
    .listStyle(.insetGrouped)
}
#endif
