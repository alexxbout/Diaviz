//
//  ChiffreAnime.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Compteur simple qui grimpe de 0 à `cible` sur `duree` secondes, en
/// passant par toutes les valeurs intermédiaires. Pas d'effet visuel
/// particulier (ni blur, ni transition stylée) — juste le chiffre qui
/// change frame par frame.
///
/// Implémenté via `TimelineView(.animation)` qui re-évalue le contenu
/// à chaque frame (~60 Hz). On dérive le progrès du temps écoulé
/// depuis `debut`, on applique un easing `easeOut`, et on affiche
/// l'entier correspondant.
///
/// Délai 250 ms aligné sur le scale du cercle parent — les deux
/// animations démarrent au même instant après l'arrivée de la sheet.
struct ChiffreAnime: View {
    let cible: Int
    let duree: TimeInterval

    @State private var debut: Date?

    var body: some View {
        TimelineView(.animation) { contexte in
            let progres: Double = {
                guard let debut else { return 0 }
                let t = contexte.date.timeIntervalSince(debut) / duree
                return min(1.0, max(0.0, t))
            }()
            // easeOut quadratique : 1 − (1 − x)² → départ rapide, fin douce.
            let eased = 1.0 - pow(1.0 - progres, 2.0)
            let valeur = Int((Double(cible) * eased).rounded())
            Text("\(valeur)")
                .monospacedDigit()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            debut = .now
        }
    }
}
