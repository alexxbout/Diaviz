//
//  AccueilVue.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Page d'accueil — carte score quotidien (résumé de la veille) et
/// futures cartes d'analyses.
///
/// Header App Store style (titre + avatar sur la même ligne) géré par
/// le composant partagé `EnTetePage`, présent à l'identique sur
/// les quatre onglets racines.
///
/// Push de `DetailScoreVue` depuis deux entrées :
///   - Tap sur la carte → push direct via `navigationDestination(item:)`
///   - Bouton « Voir les détails » de `SheetScoreMatin` → la racine
///     (`AppTabVues`) écrit dans `$jourDetailScore` après dismiss de
///     la sheet, ce qui déclenche le même push.
struct AccueilVue: View {

    /// Binding piloté par la racine (`AppTabVues`) pour pouvoir pousser
    /// le détail depuis la sheet du matin. Local par défaut quand la
    /// vue est instanciée sans binding (previews).
    @Binding var jourDetailScore: Date?

    @Environment(ProfilService.self) private var profilService

    init(jourDetailScore: Binding<Date?> = .constant(nil)) {
        self._jourDetailScore = jourDetailScore
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Accueil")

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(salutation)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary.opacity(0.78))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                            .accessibilityAddTraits(.isHeader)

                        // Carte score quotidien — données mockées en
                        // attendant la couche d'analyses.
                        CarteScoreQuotidien(
                            contenu: ContenuCarteScore(
                                score: 82,
                                date: hier,
                                historique: [65, 78, 71, 55, 88, 73, 82]
                            ),
                            style: .gradient,
                            onTap: { jourDetailScore = hier }
                        )
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(item: $jourDetailScore) { jour in
                DetailScoreVue(jourInitial: jour)
            }
        }
    }

    private var hier: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    /// Salutation contextuelle selon l'heure locale, terminée par un
    /// emoji qui suit la même progression jour → nuit.
    private var salutation: String {
        let saisi = profilService.profil.prenom
        let prenom = saisi.isEmpty ? "Camille" : saisi
        let heure = Calendar.current.component(.hour, from: Date())

        switch heure {
        case 5..<12:  return "Bonjour \(prenom) 👋"
        case 12..<18: return "Bonjour \(prenom) ☀️"
        case 18..<22: return "Bonsoir \(prenom) 🌅"
        case 22..<24: return "Bonne nuit \(prenom) 🌙"
        default:      return "Bonne nuit \(prenom) 😴"
        }
    }
}

#Preview("Avec profil complet") {
    AccueilVue()
        .environment(ProfilService.mockComplet())
}

#Preview("Profil neuf") {
    AccueilVue()
        .environment(ProfilService.mockVide())
}
