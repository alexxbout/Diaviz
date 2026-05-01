//
//  LigneActiviteSport.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

// MARK: - LigneActiviteSport
//
// Row d'une activité sportive dans la liste de la page Sport. Deux
// zones horizontales — pattern identique à la `LigneRepasJournal` :
// 1. infos texte — type avec emoji + sous-ligne (heure · durée · intensité)
// 2. mini-courbe glycémique pendant la session (largeur fixe 90pt)
//
// La row est tappable (ouvre une sheet de détail à terme — pour
// l'instant juste un placeholder dans le parent). Le swipe gauche
// expose une action "Supprimer" via `.swipeActions`.
struct LigneActiviteSport: View {

    let activite: ActiviteSportive

    /// État de la mini-courbe — calculé par le parent depuis le service
    /// (réponse pré-calculée si disponible, sinon `.donneesManquantes`).
    let etatCourbe: EtatMiniCourbeSport

    var body: some View {
        HStack(spacing: 12) {
            zoneInfos
            Spacer(minLength: 8)
            zoneCourbe
        }
        // Accessibilité : on regroupe la row pour que VoiceOver lise un
        // seul élément ("Course, 7h15, 45 minutes, modérée, glycémie
        // stable") au lieu d'énumérer les sous-vues.
        .accessibilityElement(children: .combine)
    }

    // MARK: - Zone 1 — Infos texte
    //
    // VStack(alignment: .leading) avec :
    // - label avec emoji intégré en .body
    // - sous-ligne (.caption .secondary) heure · durée · intensité
    //   (+ glucides pré-sport si renseignés)
    private var zoneInfos: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(activite.type.emoji) \(activite.type.rawValue)")
                .font(.body)
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
        var parts = [heure, duree, activite.intensite.rawValue]
        if let glucides = activite.glucidesPreSport, glucides > 0 {
            // Format compact « +15g » : le « + » suggère l'apport au
            // moment du sport, et le « g pré-sport » plus long faisait
            // tronquer la sous-ligne face à la mini-courbe à droite.
            parts.append("+\(formate(glucides))g")
        }
        return parts.joined(separator: " · ")
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

#Preview("Toutes les variantes") {
    let service = ActivitesSportServiceMock.shared

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
    }
    .listStyle(.insetGrouped)
}
