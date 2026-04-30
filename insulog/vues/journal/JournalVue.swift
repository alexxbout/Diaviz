//
//  RepasView.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct JournalVue: View {
    let nombreRepas: Int
    let sections: [(titre: String, repas: [Repas])]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // `.buttonStyle(.plain)` empêche le `NavigationLink` d'appliquer
                // sa teinte par défaut, qui surchargerait le blanc/coloré de
                // notre carte plein fond.
                NavigationLink(destination: RepasDetailVue(sections: sections)) {
                    CarteSection(
                        icone: "fork.knife",
                        titre: "Repas",
                        sousTitre: "\(nombreRepas) repas enregistré\(nombreRepas > 1 ? "s" : "") aujourd'hui",
                        couleur: .blue
                    )
                }
                .buttonStyle(.plain)

                CarteSection(
                    icone: "syringe",
                    titre: "Médications",
                    sousTitre: "Aucune médication aujourd'hui",
                    couleur: .green
                )

                CarteSection(
                    icone: "figure.run",
                    titre: "Activités sportives",
                    sousTitre: "Aucune activité aujourd'hui",
                    couleur: .orange
                )
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Journal")
        }
    }
}

private func makeDate(hour: Int, minute: Int, daysAgo: Int = 0) -> Date {
    let cal = Calendar.current
    let jour = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return cal.date(bySettingHour: hour, minute: minute, second: 0, of: jour) ?? Date()
}

// Données de preview enrichies avec `etatAnalyse` pour exercer les 6 rendus
// du `MiniCourbeReponse` (bon / moyen / mauvais / en attente / sans injection
// / données manquantes). Les états historiques (hier) sont laissés à `nil`
// pour valider le fallback "données manquantes".
//
// On passe par des sous-variables typées plutôt qu'un grand littéral imbriqué :
// le type-checker SwiftUI met sinon plusieurs secondes à inférer les tuples
// imbriqués `(titre: String, repas: [Repas])`.

private let _previewPetitDejeuner: [Repas] = [
    // Aujourd'hui — courbe verte (verdict bon)
    Repas(
        heure: makeDate(hour: 7, minute: 30),
        aliments: [
            Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
            Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
            Aliment(emoji: "🥛", nom: "Lait demi-écrémé", quantite: 200, glucides: 10, insuline: 0.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.bon)
    ),
    // Aujourd'hui — collation sans injection (tiret)
    Repas(
        heure: makeDate(hour: 9, minute: 0),
        aliments: [
            Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.sansInjection)
    ),
    // Hier — petit déj pris en hyper : la courbe démarre déjà haut
    Repas(
        heure: makeDate(hour: 8, minute: 15, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🥐", nom: "Croissant", quantite: 60, glucides: 30, insuline: 2.0),
            Aliment(emoji: "☕", nom: "Café au lait", quantite: 200, glucides: 9, insuline: 0.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.departHyper)
    ),
]

private let _previewDejeuner: [Repas] = [
    // Aujourd'hui — courbe orange (verdict moyen)
    Repas(
        heure: makeDate(hour: 12, minute: 30),
        aliments: [
            Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
            Aliment(emoji: "🍗", nom: "Poulet grillé", quantite: 150, glucides: 0, insuline: 0.0),
            Aliment(emoji: "🥦", nom: "Brocolis vapeur", quantite: 200, glucides: 8, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.moyen)
    ),
    // Aujourd'hui — repas mixte gras/glucides : double pic
    Repas(
        heure: makeDate(hour: 13, minute: 30),
        aliments: [
            Aliment(emoji: "🍔", nom: "Burger frites", quantite: 350, glucides: 75, insuline: 4.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.doublePic)
    ),
    // Hier — déjeuner pris en hyper avec correction réussie (retour en cible)
    Repas(
        heure: makeDate(hour: 13, minute: 0, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🥗", nom: "Salade César", quantite: 250, glucides: 18, insuline: 1.0),
            Aliment(emoji: "🍞", nom: "Pain complet", quantite: 60, glucides: 28, insuline: 1.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.correctionReussie)
    ),
]

private let _previewEnCas: [Repas] = [
    // Aujourd'hui — collation en cours d'analyse
    Repas(
        heure: makeDate(hour: 10, minute: 30),
        aliments: [
            Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.enAttente)
    ),
    // Aujourd'hui — goûter sans injection
    Repas(
        heure: makeDate(hour: 16, minute: 0),
        aliments: [
            Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.sansInjection)
    ),
    // Hier — bolus surdosé : pic puis hypo (courbe rouge plongeante)
    Repas(
        heure: makeDate(hour: 11, minute: 0, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🥪", nom: "Sandwich jambon-beurre", quantite: 180, glucides: 45, insuline: 4.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.hypoApresPic)
    ),
    // Hier — montagne russe : gros pic, hypo, rebond hyper après resucrage
    Repas(
        heure: makeDate(hour: 16, minute: 30, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🥨", nom: "Bretzel salé", quantite: 70, glucides: 45, insuline: 3.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.montagneRusse)
    ),
]

private let _previewDiner: [Repas] = [
    // Aujourd'hui — données CGM manquantes (icône warning)
    Repas(
        heure: makeDate(hour: 19, minute: 45),
        aliments: [
            Aliment(emoji: "🍚", nom: "Riz basmati", quantite: 70, glucides: 56, insuline: 3.0),
            Aliment(emoji: "🐟", nom: "Saumon grillé", quantite: 130, glucides: 0, insuline: 0.0),
            Aliment(emoji: "🥗", nom: "Salade verte", quantite: 80, glucides: 2, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.donneesManquantes)
    ),
    // Hier — pizza : courbe rouge à plateau haut prolongé (graisses qui ralentissent)
    Repas(
        heure: makeDate(hour: 20, minute: 30, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🍕", nom: "Pizza margherita", quantite: 300, glucides: 90, insuline: 5.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.plateauHaut)
    ),
    // Avant-hier — repas léger mais dose excessive : descente vers hypo tardive
    Repas(
        heure: makeDate(hour: 19, minute: 30, daysAgo: 2),
        aliments: [
            Aliment(emoji: "🥗", nom: "Salade composée", quantite: 200, glucides: 12, insuline: 2.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.hypoTardive)
    ),
    // Avant-hier — départ en hyper marquée + correction insuffisante
    Repas(
        heure: makeDate(hour: 20, minute: 15, daysAgo: 2),
        aliments: [
            Aliment(emoji: "🍜", nom: "Ramen porc", quantite: 400, glucides: 70, insuline: 3.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.correctionEchouee)
    ),
]

private let previewRepas: [(titre: String, repas: [Repas])] = [
    (titre: "Petit déjeuner", repas: _previewPetitDejeuner),
    (titre: "Déjeuner", repas: _previewDejeuner),
    (titre: "En-cas", repas: _previewEnCas),
    (titre: "Dîner", repas: _previewDiner),
]

#Preview("Journal") {
    JournalVue(nombreRepas: previewRepas.count, sections: previewRepas)
}
#Preview("Détail repas") {
    NavigationStack {
        RepasDetailVue(sections: previewRepas)
    }
}

