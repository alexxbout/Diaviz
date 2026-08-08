//
//  ListeRepasParSection.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct ListeRepasParSection: View {

    /// Service hub partagé via l'environnement. Source de vérité live : un repas
    /// ajouté (ou supprimé) ailleurs se reflète ici sans redémarrage.
    @Environment(RepasService.self) private var repasService

    /// Date sélectionnée par le `GrapheJourneeRepas` via swipe horizontal.
    /// Sert à filtrer les sections affichées en dessous.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Trigger du retour haptique à la suppression d'un aliment (swipe).
    @State private var triggerSuppression: Int = 0

    /// Sections du jour sélectionné, recalculées depuis le hub à chaque render
    /// (les 4 tranches canoniques). Plus de copie `@State` figée : la liste
    /// suit le service observable. Sections **sans repas enregistré** exclues
    /// — pas de "Aucun repas enregistré" répété sur les tranches vides de la
    /// journée, uniquement celles qui ont du contenu.
    private var sections: [(titre: String, repas: [Repas])] {
        repasService.sectionsDuJour(selectedDate)
            .filter { section in section.repas.contains { !$0.aliments.isEmpty } }
    }

    /// Projection à plat des repas non vides en `RepasGraph`, **tous jours
    /// confondus**. Le graphe est multi-jours (il filtre lui-même par jour) :
    /// ne lui passer que le jour sélectionné le ferait basculer sur son état
    /// vide `carteVide` (statique, sans scroll) dès qu'on atterrit sur une
    /// journée sans repas — impossible alors de re-scroller. On alimente donc
    /// depuis l'historique complet du hub, indépendamment de `selectedDate`.
    private var repasGraph: [RepasGraph] {
        let horaires = ProfilService.shared.profil.horairesRepas
        return repasService.repas
            .filter { !$0.aliments.isEmpty }
            .map { RepasGraph($0, label: SectionRepas(heure: $0.heure, horaires: horaires).titre) }
    }

    var body: some View {
        List {
            // Graph en première section, sans en-tête.
            Section {
                GrapheJourneeRepas(repas: repasGraph, selectedDate: $selectedDate)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(sections, id: \.titre) { section in
                Section(section.titre) {
                    contenuSection(section)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Repas")
        .navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.warning, trigger: triggerSuppression)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: AjouterRepasVue()) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func contenuSection(_ section: (titre: String, repas: [Repas])) -> some View {
        // `sections` ne retient que les tranches ayant au moins un repas non
        // vide — pas besoin de re-filtrer ni de message "vide" ici.
        ForEach(section.repas.filter { !$0.aliments.isEmpty }) { unRepas in
            // En-tête du repas : emoji + infos + mini-courbe glycémique.
            // Tap → détail. Pas de swipe ici : on ne supprime pas un repas
            // entier d'un geste depuis sa ligne d'en-tête.
            LigneRepas(repas: unRepas, titreSection: section.titre)

            // Ventilation des doses, motifs d'ajustement, contexte — rows
            // sœurs plutôt qu'un bloc dans l'en-tête, pour garder celui-ci
            // compact (chevron aligné sur le titre, mini-courbe dominante).
            // N'émet rien sur un repas sans correction ni ajustement.
            // `List` cale l'inset du séparateur sur le bord gauche du contenu
            // de la row — le cadre gris étant lui-même en retrait, son
            // séparateur ne partait pas du bord. On le force à 0.
            RecapDosesRepas(repas: unRepas)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

            // Détail des aliments — swipe sur un aliment le retire du hub
            // (et retire le repas s'il devient vide).
            ForEach(unRepas.aliments) { aliment in
                CarteAlimentEnregistre(
                    emoji: aliment.emojiAffiche,
                    nom: aliment.nomAffiche,
                    quantite: aliment.quantite,
                    glucides: aliment.glucides,
                    insuline: aliment.insuline,
                    imageURL: aliment.imageURL,
                    resucrage: aliment.resucrage
                )
                // Même inset forcé que le cadre gris : sans ça, une row à
                // photo produit et une row à emoji calent leur séparateur à
                // deux abscisses différentes dans la même carte.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        repasService.supprimerAliment(aliment, de: unRepas)
                        triggerSuppression += 1
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
        }
    }
}

// MARK: - Aperçu

#Preview("Avec repas") {
    NavigationStack {
        ListeRepasParSection()
    }
    .environment(RepasService.apercu())
}

#Preview("Journée vide") {
    NavigationStack {
        ListeRepasParSection()
    }
    .environment(RepasService())
}
