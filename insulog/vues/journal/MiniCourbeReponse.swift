//
//  MiniCourbeReponse.swift
//  insulog
//
//  Created by Alexandre on 30/04/2026.
//

import Charts
import SwiftUI

// MARK: - MiniCourbeReponse
//
// Aperçu compact (90×48pt) de la réponse glycémique post-repas, conçu
// pour s'intégrer dans la `LigneRepasJournal` sans surcharger visuellement
// la liste. La vue route entre 4 états — la courbe Swift Charts n'est
// rendue que dans le cas `disponible`.
struct MiniCourbeReponse: View {

    let etat: EtatAnalyse

    // Dimensions cibles : la zone est fixe pour ne pas perturber la grille
    // de la row (texte + courbe alignés sur la même hauteur).
    private static let largeur: CGFloat = 90
    private static let hauteur: CGFloat = 48

    var body: some View {
        Group {
            switch etat {
            case .disponible(let reponse):
                CourbeDisponible(reponse: reponse)
            case .enAttente(let minutesRestantes):
                indicateurAttente(minutesRestantes: minutesRestantes)
            case .donneesManquantes:
                indicateurDonneesManquantes
            case .sansInjection:
                indicateurSansInjection
            }
        }
        .frame(width: Self.largeur, height: Self.hauteur)
    }

    // MARK: - Cas "en attente"
    //
    // Icône horloge + petite légende avec le délai restant compact ("1h30",
    // "30min"). Le délai textuel sous l'icône est ce qui rend l'état
    // explicitement compréhensible — l'icône seule était trop abstraite.
    @ViewBuilder
    private func indicateurAttente(minutesRestantes: Int) -> some View {
        IndicateurTapLong(
            systemImage: "clock.fill",
            legendeTexte: etiquetteAttente(minutesRestantes: minutesRestantes),
            descriptionAccessibilite: messageAttente(minutesRestantes: minutesRestantes),
            messageTooltip: messageAttente(minutesRestantes: minutesRestantes)
        )
    }

    private var indicateurDonneesManquantes: some View {
        IndicateurTapLong(
            systemImage: "exclamationmark.triangle",
            legendeTexte: "Pas de CGM",
            descriptionAccessibilite: "Données CGM insuffisantes",
            messageTooltip: "Données CGM insuffisantes"
        )
    }

    // MARK: - Cas "sans injection"
    private var indicateurSansInjection: some View {
        Text("—")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Repas sans injection — pas d'analyse")
    }

    // MARK: - Helpers

    /// Délai restant formaté pour la légende compacte sous l'icône horloge.
    /// Format français usuel : "30min", "1h", "1h30" — sans espaces pour
    /// tenir dans les ~90pt de la zone de courbe.
    private func etiquetteAttente(minutesRestantes: Int) -> String {
        let minutes = max(0, minutesRestantes)
        if minutes < 60 { return "\(minutes)min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    /// Texte plus long destiné au popover (tap long) et à VoiceOver.
    private func messageAttente(minutesRestantes: Int) -> String {
        let minutes = max(0, minutesRestantes)
        if minutes < 60 {
            return "Analyse dans \(minutes)min"
        }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "Analyse dans \(h)h" : "Analyse dans \(h)h \(m)min"
    }
}

// MARK: - CourbeDisponible
//
// Sous-vue dédiée au rendu de la courbe Swift Charts. L'extraction permet
// de garder le `body` de `MiniCourbeReponse` lisible et facilite le
// type-checking (les `Chart` à plusieurs marks sont coûteux à inférer).
private struct CourbeDisponible: View {

    let reponse: ReponseGlycemique

    var body: some View {
        Chart {
            // 1. La courbe glycémique. `ForEach` plutôt que
            //    `Chart(reponse.pointsCgm)` parce qu'on combine plusieurs
            //    types de marks dans le même graphe.
            ForEach(reponse.pointsCgm) { point in
                LineMark(
                    x: .value("Temps", point.secondesDepuisRepas),
                    y: .value("Glycémie", point.valeur)
                )
                .foregroundStyle(reponse.verdict.couleur)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            // 2. Marqueur T0 — petit cercle gris qui ancre l'instant du repas
            //    sur la courbe. Volontairement discret : ce n'est pas le focus.
            PointMark(
                x: .value("Temps", 0),
                y: .value("Glycémie", valeurT0)
            )
            .symbol(.circle)
            .symbolSize(15)
            .foregroundStyle(.secondary)

            // 3. Marqueur du pic — point plein, plus gros, dans la couleur du
            //    verdict, surmonté de la valeur numérique en mg/dL.
            PointMark(
                x: .value("Temps", reponse.tempsPic),
                y: .value("Glycémie", reponse.valeurPic)
            )
            .symbol(.circle)
            .symbolSize(50)
            .foregroundStyle(reponse.verdict.couleur)
            .annotation(position: .top, alignment: .center, spacing: 2) {
                Text("\(Int(reponse.valeurPic))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(reponse.verdict.couleur)
            }

            // 4. Marqueur du point le plus bas — affiché uniquement quand la
            //    courbe plonge sous la baseline pré-repas (cas hypo). Sinon
            //    c'est juste le retour normal en cible et ça surcharge la vue.
            if let pointMin = pointMinAAfficher {
                PointMark(
                    x: .value("Temps", pointMin.secondesDepuisRepas),
                    y: .value("Glycémie", pointMin.valeur)
                )
                .symbol(.circle)
                .symbolSize(50)
                .foregroundStyle(reponse.verdict.couleur)
                .annotation(position: .bottom, alignment: .center, spacing: 2) {
                    Text("\(Int(pointMin.valeur))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(reponse.verdict.couleur)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // Échelle X fixe : T-1h à T+4h. L'axe est caché mais l'échelle pilote
        // le placement horizontal des marks et garantit que toutes les
        // courbes ont la même largeur temporelle (comparables visuellement).
        .chartXScale(domain: -3600...14400)
        .chartYScale(domain: yAxisDomain)
        // 12pt en haut ET en bas pour laisser place aux annotations textuelles
        // (valeur du pic en haut, valeur du minimum en bas — quand affiché).
        // Padding constant pour éviter que la zone du tracé saute en hauteur
        // d'une row à l'autre selon que le min est annoté ou pas.
        .chartPlotStyle { plot in
            plot.padding(.vertical, 12)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(reponse.verdict.descriptionAccessibilite))
        .accessibilityValue(Text(descriptionVoiceOver))
    }

    /// Glycémie à T=0 (instant exact du repas). La fenêtre étant échantillonnée
    /// par pas de 5min à partir de -3600s, un point tombe pile sur 0 — on le
    /// récupère directement, avec un fallback sur le point le plus proche.
    private var valeurT0: Double {
        if let pile = reponse.pointsCgm.first(where: { $0.secondesDepuisRepas == 0 }) {
            return pile.valeur
        }
        return reponse.pointsCgm
            .min(by: { abs($0.secondesDepuisRepas) < abs($1.secondesDepuisRepas) })?
            .valeur ?? 110
    }

    /// Point le plus bas de la courbe post-repas, **à condition** qu'il
    /// plonge significativement sous la baseline T0 (≥ 15 mg/dL en dessous).
    /// Sinon, le min est juste le retour en cible — pas la peine de l'annoter.
    /// Seuil 15 mg/dL : empirique, suffisant pour distinguer un vrai creux
    /// (hypo, sortie de cible par le bas) d'un simple retour stable.
    private var pointMinAAfficher: PointCgm? {
        let postRepas = reponse.pointsCgm.filter { $0.secondesDepuisRepas >= 0 }
        guard let min = postRepas.min(by: { $0.valeur < $1.valeur }) else { return nil }
        guard min.valeur < valeurT0 - 15 else { return nil }
        return min
    }

    /// Domaine Y dynamique : bornes basées sur les valeurs effectives de la
    /// courbe (avec un peu d'air en haut/bas). Le marqueur du pic — et
    /// éventuellement du minimum — sera ainsi toujours dans la zone de tracé.
    private var yAxisDomain: ClosedRange<Double> {
        let valeurs = reponse.pointsCgm.map(\.valeur)
        let mini = (valeurs.min() ?? 70) - 5
        let maxi = (valeurs.max() ?? 200) + 5
        return mini...maxi
    }

    /// Texte VoiceOver mentionnant le pic et, le cas échéant, le minimum.
    private var descriptionVoiceOver: String {
        var parts: [String] = ["Pic à \(Int(reponse.valeurPic)) milligrammes par décilitre"]
        if let min = pointMinAAfficher {
            parts.append("minimum à \(Int(min.valeur))")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - IndicateurTapLong
//
// Sous-composant dédié à l'indicateur d'état (icône + légende textuelle
// courte) avec popover au tap long. Centralise la mécanique pour les cas
// `enAttente` et `donneesManquantes`, qui partagent exactement le même
// pattern visuel et d'interaction.
//
// L'icône seule s'est révélée peu parlante en contexte de mini-courbe —
// la légende `caption2` sous l'icône donne la sémantique explicite ("1h30",
// "Pas de CGM") sans dépendre de l'interprétation du symbole.
private struct IndicateurTapLong: View {
    let systemImage: String
    let legendeTexte: String
    let descriptionAccessibilite: String
    let messageTooltip: String

    @State private var afficheTooltip = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            Text(legendeTexte)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Tap simple → laissé à la row parente. Tap long (≥ 0.5s) → popover.
        .onLongPressGesture(minimumDuration: 0.5) {
            afficheTooltip = true
        }
        .popover(isPresented: $afficheTooltip, arrowEdge: .bottom) {
            Text(messageTooltip)
                .font(.caption)
                .padding(8)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityElement()
        .accessibilityLabel(descriptionAccessibilite)
        .accessibilityHint("Tap long pour plus de détails")
    }
}

// MARK: - Aperçu

#Preview("Tous les états") {
    ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitre("Verdicts standards")
            ligneApercu("Bon", etat: ReponseGlycemiqueServiceMock.cas(.bon))
            ligneApercu("Moyen", etat: ReponseGlycemiqueServiceMock.cas(.moyen))
            ligneApercu("Mauvais", etat: ReponseGlycemiqueServiceMock.cas(.mauvais))

            sectionTitre("Hypoglycémies")
            ligneApercu("Hypo après pic", etat: ReponseGlycemiqueServiceMock.cas(.hypoApresPic))
            ligneApercu("Hypo tardive", etat: ReponseGlycemiqueServiceMock.cas(.hypoTardive))

            sectionTitre("Variations hautes")
            ligneApercu("Double pic (mixte)", etat: ReponseGlycemiqueServiceMock.cas(.doublePic))
            ligneApercu("Plateau haut", etat: ReponseGlycemiqueServiceMock.cas(.plateauHaut))

            sectionTitre("Départs en hyper")
            ligneApercu("Repas en hyper", etat: ReponseGlycemiqueServiceMock.cas(.departHyper))
            ligneApercu("Correction réussie", etat: ReponseGlycemiqueServiceMock.cas(.correctionReussie))
            ligneApercu("Correction échouée", etat: ReponseGlycemiqueServiceMock.cas(.correctionEchouee))

            sectionTitre("Mixtes")
            ligneApercu("Montagne russe", etat: ReponseGlycemiqueServiceMock.cas(.montagneRusse))

            sectionTitre("États non-disponibles")
            ligneApercu("En attente", etat: ReponseGlycemiqueServiceMock.cas(.enAttente))
            ligneApercu("Sans injection", etat: ReponseGlycemiqueServiceMock.cas(.sansInjection))
            ligneApercu("Données manquantes", etat: ReponseGlycemiqueServiceMock.cas(.donneesManquantes))
        }
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}

@ViewBuilder
private func sectionTitre(_ titre: String) -> some View {
    Text(titre)
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
}

@ViewBuilder
private func ligneApercu(_ titre: String, etat: EtatAnalyse) -> some View {
    HStack {
        Text(titre)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 160, alignment: .leading)
        MiniCourbeReponse(etat: etat)
            .background(Color(.secondarySystemBackground))
    }
}
