//
//  MiniCourbeReponse.swift
//  insulog
//
//  Created by Alexandre on 30/04/2026.
//

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
                CourbeMiniReponse(reponse: reponse)
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
