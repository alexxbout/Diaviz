//
//  MiniCourbeSport.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import Charts
import SwiftUI

// MARK: - MiniCourbeSport
//
// Aperçu compact (90×48pt) de la réponse glycémique pendant une session
// sportive, pour s'intégrer dans la `LigneActiviteSport` sans surcharger
// visuellement la liste. Inspirée strictement de `MiniCourbeReponse`
// (page Repas), mais avec un sens différent :
// - les marqueurs sont **début** et **fin** de session (pas T0/pic) ;
// - le verdict est basé sur la stabilité glycémique pendant l'effort
//   et la détection d'hypo (pas sur le pic post-prandial) ;
// - la ligne de référence est tracée à 70 mg/dL (limite hypo).
struct MiniCourbeSport: View {

    /// État de l'analyse — réponse pré-calculée si disponible, ou `nil`
    /// si données CGM insuffisantes (par défaut on considère « manquant »).
    let etat: EtatMiniCourbeSport

    /// Durée de la session (utilisée pour positionner le marqueur de fin).
    let dureeMinutes: Int

    // Dimensions cibles : la zone est fixe pour garder un alignement
    // homogène entre toutes les rows de la liste.
    private static let largeur: CGFloat = 90
    private static let hauteur: CGFloat = 48

    var body: some View {
        Group {
            switch etat {
            case .disponible(let reponse):
                CourbeDisponible(reponse: reponse, dureeMinutes: dureeMinutes)
            case .enAttente(let minutesRestantes):
                indicateurAttente(minutesRestantes: minutesRestantes)
            case .donneesManquantes:
                indicateurDonneesManquantes
            }
        }
        .frame(width: Self.largeur, height: Self.hauteur)
    }

    // MARK: - États non-disponibles
    //
    // Pattern identique à `MiniCourbeReponse` : icône + légende courte,
    // pas de courbe partielle. La sémantique « sansInjection » n'a pas
    // d'équivalent ici (toute activité a une réponse glycémique
    // observable s'il y a du CGM disponible).

    @ViewBuilder
    private func indicateurAttente(minutesRestantes: Int) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "clock.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            Text(etiquetteAttente(minutesRestantes: minutesRestantes))
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Analyse en attente, \(etiquetteAttente(minutesRestantes: minutesRestantes))")
    }

    private var indicateurDonneesManquantes: some View {
        VStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            Text("Pas de CGM")
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Données CGM insuffisantes")
    }

    // MARK: - Helpers

    /// Délai restant formaté pour la légende compacte sous l'icône.
    /// Format français usuel : "30min", "1h", "1h30" — sans espaces
    /// pour tenir dans les ~90pt de la zone de courbe.
    private func etiquetteAttente(minutesRestantes: Int) -> String {
        let minutes = max(0, minutesRestantes)
        if minutes < 60 { return "\(minutes)min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }
}

// MARK: - EtatMiniCourbeSport
//
// État de l'analyse pour la mini-courbe sport. Volontairement plus
// compact que `EtatAnalyse` (page Repas) — on ne distingue pas le cas
// `sansInjection` qui n'a pas de sens ici.
enum EtatMiniCourbeSport {
    case disponible(ReponseGlycemiqueSport)
    case enAttente(minutesRestantes: Int)
    case donneesManquantes
}

// MARK: - CourbeDisponible
//
// Sous-vue dédiée au rendu de la courbe Swift Charts. L'extraction
// permet de garder le `body` de `MiniCourbeSport` lisible et facilite
// le type-checking (les `Chart` à plusieurs marks sont coûteux à
// inférer).
private struct CourbeDisponible: View {

    let reponse: ReponseGlycemiqueSport
    let dureeMinutes: Int

    /// Couleur du verdict — basée sur la stabilité glycémique pendant
    /// l'effort et la détection d'hypoglycémie. Différent du verdict
    /// repas : ici on récompense la **stabilité** (pas un pic suivi
    /// d'un retour en cible).
    ///
    /// - rouge si la glycémie de fin est en hypoglycémie (< 70 mg/dL)
    /// - vert si variation < 20 mg/dL (séance bien gérée)
    /// - orange si chute > 40 mg/dL (descente importante, risque)
    /// - bleu sinon (variation modérée — neutre)
    private var couleurVerdict: Color {
        if reponse.glycemieFin < 70 {
            return .red
        }
        if abs(reponse.deltaMgDl) < 20 {
            return .green
        }
        if reponse.deltaMgDl < -40 {
            return .orange
        }
        return .blue
    }

    /// Durée de la session en secondes — utilisée pour positionner le
    /// marqueur de fin sur l'axe X.
    private var dureeEnSecondes: TimeInterval {
        TimeInterval(dureeMinutes * 60)
    }

    var body: some View {
        Chart {
            // 1. Ligne de référence à 70 mg/dL (limite hypo). Pointillé
            //    discret — ancre visuelle pour repérer une hypoglycémie
            //    en un coup d'œil, sans surcharger.
            RuleMark(y: .value("Hypo", 70))
                .foregroundStyle(.secondary.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

            // 2. La courbe glycémique. `ForEach` plutôt que
            //    `Chart(reponse.pointsCgm)` parce qu'on combine
            //    plusieurs types de marks dans le même graphe.
            ForEach(reponse.pointsCgm) { point in
                LineMark(
                    x: .value("Temps", point.secondesDepuisDebut),
                    y: .value("Glycémie", point.valeur)
                )
                .foregroundStyle(couleurVerdict)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            // 3. Marqueur début de session — petit cercle ouvert gris
            //    qui ancre visuellement le t=0. Volontairement discret :
            //    ce n'est pas le focus, juste la référence.
            PointMark(
                x: .value("Temps", 0),
                y: .value("Glycémie", reponse.glycemieDebut)
            )
            .symbol(.circle)
            .symbolSize(15)
            .foregroundStyle(.secondary)
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text("\(Int(reponse.glycemieDebut))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // 4. Marqueur fin de session — point plein, plus gros, dans
            //    la couleur du verdict, surmonté de la valeur numérique.
            //    C'est le point d'attention principal — il porte la
            //    « note » de la session.
            PointMark(
                x: .value("Temps", dureeEnSecondes),
                y: .value("Glycémie", reponse.glycemieFin)
            )
            .symbol(.circle)
            .symbolSize(50)
            .foregroundStyle(couleurVerdict)
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                Text("\(Int(reponse.glycemieFin))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(couleurVerdict)
                    .monospacedDigit()
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yAxisDomain)
        // Padding vertical pour laisser place aux annotations textuelles
        // au-dessus des marqueurs (valeurs de début/fin). Constant pour
        // que la zone de tracé ne saute pas en hauteur d'une row à l'autre.
        .chartPlotStyle { plot in
            plot.padding(.vertical, 12)
        }
        .accessibilityElement()
        .accessibilityLabel(descriptionAccessibilite)
        .accessibilityValue(descriptionVoiceOver)
    }

    /// Domaine Y dynamique : bornes basées sur les valeurs effectives
    /// de la courbe (avec un peu d'air en haut/bas) ET la ligne de
    /// référence à 70 mg/dL pour qu'elle reste toujours visible.
    private var yAxisDomain: ClosedRange<Double> {
        let valeurs = reponse.pointsCgm.map(\.valeur)
        let mini = min((valeurs.min() ?? 70) - 5, 65)
        let maxi = (valeurs.max() ?? 130) + 5
        return mini...maxi
    }

    /// Label sémantique pour VoiceOver — résume le verdict en une
    /// phrase courte que l'utilisateur peut comprendre sans voir
    /// la courbe.
    private var descriptionAccessibilite: String {
        if reponse.glycemieFin < 70 {
            return "Hypoglycémie en fin de séance"
        }
        if abs(reponse.deltaMgDl) < 20 {
            return "Glycémie stable pendant la séance"
        }
        if reponse.deltaMgDl < -40 {
            return "Chute glycémique importante"
        }
        return "Variation glycémique modérée"
    }

    /// Détail VoiceOver : valeurs exactes de début et fin.
    private var descriptionVoiceOver: Text {
        Text("De \(Int(reponse.glycemieDebut)) à \(Int(reponse.glycemieFin)) milligrammes par décilitre")
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Tous les états") {
    let service = ActivitesSportService.apercu()
    let activites = service.activites.prefix(4)

    return ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Données disponibles")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            ForEach(Array(activites), id: \.id) { activite in
                HStack {
                    Label(activite.type.rawValue, systemImage: activite.type.icone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 160, alignment: .leading)
                    if let reponse = service.reponse(pour: activite) {
                        MiniCourbeSport(
                            etat: .disponible(reponse),
                            dureeMinutes: activite.dureeMinutes
                        )
                        .background(Color(.secondarySystemBackground))
                    }
                }
            }

            Text("États non-disponibles")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            HStack {
                Text("En attente (1h30)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 160, alignment: .leading)
                MiniCourbeSport(etat: .enAttente(minutesRestantes: 90), dureeMinutes: 45)
                    .background(Color(.secondarySystemBackground))
            }

            HStack {
                Text("Données manquantes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 160, alignment: .leading)
                MiniCourbeSport(etat: .donneesManquantes, dureeMinutes: 45)
                    .background(Color(.secondarySystemBackground))
            }
        }
        .padding()
    }
}
#endif
