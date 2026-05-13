//
//  RepasView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct JournalVue: View {
    let nombreRepas: Int
    let sections: [(titre: String, repas: [Repas])]

    /// Service d'import HealthKit — injecté depuis la racine de l'app
    /// via `@Environment`. Alimente le badge rouge superposé à la
    /// carte « Activités sportives » quand des workouts sont en attente
    /// d'import.
    @Environment(HealthKitImportService.self) private var importService

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Journal")

                VStack(alignment: .leading, spacing: 16) {
                    // `.buttonStyle(.plain)` empêche le `NavigationLink` d'appliquer
                    // sa teinte par défaut, qui surchargerait le blanc/coloré de
                    // notre carte plein fond.
                    NavigationLink(destination: ListeRepasParSection(sections: sections)) {
                        CarteSection(
                            icone: "fork.knife",
                            titre: "Repas",
                            sousTitre: "\(nombreRepas) repas enregistré\(nombreRepas > 1 ? "s" : "") aujourd'hui",
                            couleur: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: MedicationsVue()) {
                        CarteSection(
                            icone: "syringe",
                            titre: "Médications",
                            sousTitre: "Aucune médication aujourd'hui",
                            couleur: .green
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: SportVue()) {
                        CarteSection(
                            icone: "figure.run",
                            titre: "Activités sportives",
                            sousTitre: "Aucune activité aujourd'hui",
                            couleur: .orange
                        )
                        .overlay(alignment: .topTrailing) { badgeImport }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    /// Pastille rouge en haut à droite de la carte sport — n'apparaît
    /// que si le service signale des activités à importer. Animation
    /// `easeInOut` pour qu'elle apparaisse/disparaisse en douceur quand
    /// l'utilisateur traite ou ignore depuis la sheet.
    @ViewBuilder
    private var badgeImport: some View {
        if importService.aDesImportsEnAttente {
            Text("\(importService.nombreEnAttente)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red, in: Capsule())
                .padding(12)
                .accessibilityLabel("\(importService.nombreEnAttente) activités Apple Santé à importer")
                .transition(.scale.combined(with: .opacity))
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

// IOB renseigné de manière narrativement cohérente :
// - Petit-déj : 0u (premier repas de la journée, pas de bolus récent)
// - Collation 9h : 1.5u (résidu du petit-déj qui agit encore)
// - Déjeuner : 0.6u (résidu de la collation matinale)
// - En-cas 16h : 2.2u (résidu du bolus du déjeuner ~3h plus tôt)
// - Bolus surdosé sandwich : 0u (premier bolus après nuit)
//   — l'hypo vient d'une dose excessive, pas d'IOB cumulé.
private let _previewPetitDejeuner: [Repas] = [
    // Aujourd'hui — courbe verte (verdict bon)
    Repas(
        heure: makeDate(hour: 7, minute: 30),
        aliments: [
            Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
            Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
            Aliment(emoji: "🥛", nom: "Lait demi-écrémé", quantite: 200, glucides: 10, insuline: 0.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.bon),
        iobAuDebut: nil
    ),
    // Aujourd'hui — collation sans injection (tiret). IOB modéré
    // (1.5u du petit-déj) → exerce le badge orange « Élevé ».
    Repas(
        heure: makeDate(hour: 9, minute: 0),
        aliments: [
            Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.sansInjection),
        iobAuDebut: 1.5
    ),
    // Hier — petit déj pris en hyper : la courbe démarre déjà haut
    Repas(
        heure: makeDate(hour: 8, minute: 15, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🥐", nom: "Croissant", quantite: 60, glucides: 30, insuline: 2.0),
            Aliment(emoji: "☕", nom: "Café au lait", quantite: 200, glucides: 9, insuline: 0.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.departHyper),
        iobAuDebut: nil
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
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.moyen),
        iobAuDebut: 0.6
    ),
    // Aujourd'hui — repas mixte gras/glucides : double pic
    Repas(
        heure: makeDate(hour: 13, minute: 30),
        aliments: [
            Aliment(emoji: "🍔", nom: "Burger frites", quantite: 350, glucides: 75, insuline: 4.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.doublePic),
        iobAuDebut: nil
    ),
    // Hier — déjeuner pris en hyper avec correction réussie (retour en cible)
    Repas(
        heure: makeDate(hour: 13, minute: 0, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🥗", nom: "Salade César", quantite: 250, glucides: 18, insuline: 1.0),
            Aliment(emoji: "🍞", nom: "Pain complet", quantite: 60, glucides: 28, insuline: 1.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.correctionReussie),
        iobAuDebut: nil
    ),
]

private let _previewEnCas: [Repas] = [
    // Aujourd'hui — collation en cours d'analyse
    Repas(
        heure: makeDate(hour: 10, minute: 30),
        aliments: [
            Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.enAttente),
        iobAuDebut: 0.8
    ),
    // Aujourd'hui — goûter sans injection. IOB élevé (résidu du
    // déjeuner) → exerce le badge rouge « Très élevé », explique
    // pourquoi pas de bolus sur ce goûter.
    Repas(
        heure: makeDate(hour: 16, minute: 0),
        aliments: [
            Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.sansInjection),
        iobAuDebut: 2.2
    ),
    // Hier — bolus surdosé : pic puis hypo (courbe rouge plongeante).
    // Pas d'IOB au démarrage : le surdosage vient de la dose initiale,
    // l'hypo permet de tester le marqueur sur le graphique détail.
    Repas(
        heure: makeDate(hour: 11, minute: 0, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🥪", nom: "Sandwich jambon-beurre", quantite: 180, glucides: 45, insuline: 4.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.hypoApresPic),
        iobAuDebut: nil
    ),
    // Hier — montagne russe : gros pic, hypo, rebond hyper après resucrage
    Repas(
        heure: makeDate(hour: 16, minute: 30, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🥨", nom: "Bretzel salé", quantite: 70, glucides: 45, insuline: 3.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.montagneRusse),
        iobAuDebut: 1.2
    ),
]

private let _previewDiner: [Repas] = [
    // Aujourd'hui — données CGM manquantes (icône warning).
    // IOB modéré (résidu du goûter de 16h).
    Repas(
        heure: makeDate(hour: 19, minute: 45),
        aliments: [
            Aliment(emoji: "🍚", nom: "Riz basmati", quantite: 70, glucides: 56, insuline: 3.0),
            Aliment(emoji: "🐟", nom: "Saumon grillé", quantite: 130, glucides: 0, insuline: 0.0),
            Aliment(emoji: "🥗", nom: "Salade verte", quantite: 80, glucides: 2, insuline: 0.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.donneesManquantes),
        iobAuDebut: 0.4
    ),
    // Hier — pizza : courbe rouge à plateau haut prolongé (graisses qui ralentissent)
    Repas(
        heure: makeDate(hour: 20, minute: 30, daysAgo: 1),
        aliments: [
            Aliment(emoji: "🍕", nom: "Pizza margherita", quantite: 300, glucides: 90, insuline: 5.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.plateauHaut),
        iobAuDebut: nil
    ),
    // Avant-hier — repas léger mais dose excessive : descente vers hypo tardive
    Repas(
        heure: makeDate(hour: 19, minute: 30, daysAgo: 2),
        aliments: [
            Aliment(emoji: "🥗", nom: "Salade composée", quantite: 200, glucides: 12, insuline: 2.0),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.hypoTardive),
        iobAuDebut: nil
    ),
    // Avant-hier — départ en hyper marquée + correction insuffisante
    Repas(
        heure: makeDate(hour: 20, minute: 15, daysAgo: 2),
        aliments: [
            Aliment(emoji: "🍜", nom: "Ramen porc", quantite: 400, glucides: 70, insuline: 3.5),
        ],
        etatAnalyse: ReponseGlycemiqueServiceMock.cas(.correctionEchouee),
        iobAuDebut: 0.7
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
        .environment(HealthKitImportService.mockVide())
        .environment(ProfilService.mockComplet())
}

#Preview("Journal - Avec badge") {
    JournalVue(nombreRepas: previewRepas.count, sections: previewRepas)
        .environment(HealthKitImportService.mockAvecActivites([
            .mockCourse, .mockYoga
        ]))
        .environment(ProfilService.mockComplet())
}

#Preview("Détail repas") {
    NavigationStack {
        ListeRepasParSection(sections: previewRepas)
    }
}

