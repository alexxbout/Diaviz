//
//  PageInventaireDonnees.swift
//  diaviz
//

import SwiftData
import SwiftUI

/// Page « Depuis le début » — inventaire de ce que contient le hub : combien
/// de repas, d'injections, de séances, de resucrages, et depuis quand.
///
/// **Un inventaire, pas une analyse.** Aucun de ces chiffres n'est confronté
/// à un seuil ni jugé : ils décrivent le contenu de l'app, pas l'état de
/// santé. C'est aussi ce qui répond, mieux qu'un message d'attente, à la
/// question « pourquoi telle analyse est encore muette ».
///
/// Deux entrées vers cet écran — Profil → Données, et le Journal — comme la
/// sheet « Écart de ratio » : l'inventaire appartient au corpus (donc aux
/// réglages de données), mais le réflexe « où sont mes données » pointe vers
/// le Journal.
struct PageInventaireDonnees: View {

    @Environment(\.modelContext) private var modelContext

    /// `nil` tant que le hub n'a pas été interrogé — l'écran n'affiche pas une
    /// colonne de zéros pendant le chargement.
    @State private var inventaire: InventaireDonnees?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EnTeteAnalyse(
                    surtitre: "Mes données",
                    titre: "Depuis le début",
                    accroche: accrocheEnTete,
                    ambiance: .donnees
                )

                if let inventaire {
                    if inventaire.estVide {
                        CartePlaceholderAccueil(
                            icone: "tray",
                            message: "Rien d'enregistré pour l'instant. Repas, injections, séances et resucrages seront comptés ici."
                        )
                    } else {
                        tuiles(inventaire)
                        trameSaisie(inventaire)
                        streakSaisie(inventaire)
                        detail(inventaire)
                        mentionPortee
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mes données")
        .navigationBarTitleDisplayMode(.inline)
        .task { inventaire = ChargeurInventaire.charger(contexte: modelContext) }
    }

    private var accrocheEnTete: String {
        guard let inventaire, let premiere = inventaire.premiereSaisie else {
            return "Tout ce que vous avez enregistré dans l'app."
        }
        let jour = premiere.formatted(.dateTime.day().month(.wide).year())
        return "Tout ce que vous avez enregistré depuis le \(jour)."
    }

    // MARK: - Tuiles

    /// Les quatre volumes qu'on veut lire en une seconde. Grille adaptative
    /// plutôt que deux colonnes figées : en très gros corps de texte, une
    /// tuile par ligne reste lisible là où deux se tronqueraient.
    private func tuiles(_ i: InventaireDonnees) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            tuile(titre: "Repas", valeur: "\(i.repas)", detail: "\(i.glucidesTotal) g de glucides")
            tuile(titre: "Injections", valeur: "\(i.injections)", detail: "\(i.unitesTotal.doseInsulineFormatee) au total")
            tuile(titre: "Séances", valeur: "\(i.seances)", detail: dureeCumulee(i.minutesSport))
            tuile(titre: "Glycémies", valeur: "\(i.glycemies)", detail: "via Apple Santé")
        }
    }

    private func tuile(titre: String, valeur: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(valeur)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre) : \(valeur), \(detail)")
    }

    // MARK: - Trame de régularité

    /// Un carré par jour sur deux semaines. Ce n'est pas un score de
    /// discipline : la densité de saisie explique simplement ce dont les
    /// analyses disposent pour travailler.
    private func trameSaisie(_ i: InventaireDonnees) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Régularité de saisie")
                    .font(.subheadline.weight(.medium))
                Text("Un carré par jour sur les \(CalculInventaireDonnees.joursTrame) derniers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(i.saisiesParJour) { point in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(couleurTrame(point.saisies))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Saisies des \(CalculInventaireDonnees.joursTrame) derniers jours")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCarte()
    }

    /// Quatre paliers seulement : au-delà, l'œil ne distingue plus les
    /// nuances et la trame prétend à une précision qu'elle n'a pas.
    private func couleurTrame(_ saisies: Int) -> Color {
        switch saisies {
        case 0:     Color(.tertiarySystemFill)
        case 1...2: Color.indigo.opacity(0.35)
        case 3...5: Color.indigo.opacity(0.65)
        default:    Color.indigo
        }
    }

    // MARK: - Streak de saisie

    /// Jours consécutifs avec au moins une saisie manuelle, et record.
    /// Un score d'usage de l'app, pas de santé : n'a aucun lien avec la
    /// glycémie, ne juge rien, ne notifie rien.
    private func streakSaisie(_ i: InventaireDonnees) -> some View {
        HStack(spacing: 0) {
            streakColonne(titre: "Streak actuel", valeur: i.streakActuel)
            Divider().frame(height: 32)
            streakColonne(titre: "Record", valeur: i.streakRecord)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streak actuel : \(i.streakActuel) jour\(i.streakActuel > 1 ? "s" : ""). Record : \(i.streakRecord) jour\(i.streakRecord > 1 ? "s" : "").")
    }

    private func streakColonne(titre: String, valeur: Int) -> some View {
        VStack(spacing: 2) {
            Text(titre)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(valeur > 0 ? "\(valeur) j" : "—")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Détail

    private func detail(_ i: InventaireDonnees) -> some View {
        VStack(spacing: 0) {
            ligne("Repas", valeur: "\(i.repas)", detail: "\(i.glucidesTotal) g de glucides")
            Divider().padding(.leading, 16)
            ligne(
                "Injections", valeur: "\(i.injections)",
                detail: "\(i.injectionsRapides) rapides · \(i.injectionsLentes) lentes · \(i.unitesTotal.doseInsulineFormatee)"
            )
            Divider().padding(.leading, 16)
            ligne("Séances de sport", valeur: "\(i.seances)", detail: "\(dureeCumulee(i.minutesSport)) cumulées")
            Divider().padding(.leading, 16)
            ligne(
                "Resucrages", valeur: "\(i.resucrages)",
                detail: "\(i.resucragesCorrectifs) correctifs · \(i.resucragesPreventifs) préventifs"
            )
            Divider().padding(.leading, 16)
            ligne(
                "Jours avec au moins un repas",
                valeur: "\(i.joursAvecRepas) / \(i.joursCouverts)",
                detail: nil
            )
        }
        .surfaceCarte()
    }

    private func ligne(_ libelle: String, valeur: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(libelle)
                    .font(.body)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(valeur)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var mentionPortee: some View {
        Label(
            "Ces compteurs décrivent ce que contient l'app, pas votre état de santé.",
            systemImage: "info.circle"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// « 7 h 20 » / « 45 min » — les heures cumulées d'un sport se lisent mal
    /// en minutes dès qu'on dépasse la centaine.
    private func dureeCumulee(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }
}

// MARK: - Chargement depuis le hub

/// Lit le hub une fois, à l'ouverture de la page, et le réduit aux valeurs
/// que compte `CalculInventaireDonnees`.
///
/// Les glycémies passent par `fetchCount` : elles se comptent par milliers,
/// les charger pour les dénombrer serait absurde. Les autres familles sont
/// chargées entièrement — quelques centaines d'objets au grand maximum, et il
/// faut de toute façon leurs grandeurs cumulables.
private enum ChargeurInventaire {

    @MainActor
    static func charger(contexte: ModelContext) -> InventaireDonnees {
        var entrees: [EntreeInventaire] = []

        let repas = (try? contexte.fetch(FetchDescriptor<Repas>())) ?? []
        entrees += repas.map {
            EntreeInventaire(date: $0.heure, domaine: .repas(glucides: $0.totalGlucides))
        }

        let injections = (try? contexte.fetch(FetchDescriptor<Injection>())) ?? []
        entrees += injections.map {
            EntreeInventaire(date: $0.heure, domaine: .injection(unites: $0.dose, lente: $0.type == .lente))
        }

        let activites = (try? contexte.fetch(FetchDescriptor<ActiviteSportive>())) ?? []
        entrees += activites.map {
            EntreeInventaire(date: $0.dateDebut, domaine: .sport(minutes: $0.dureeMinutes))
        }

        let resucrages = (try? contexte.fetch(FetchDescriptor<Resucrage>())) ?? []
        entrees += resucrages.map {
            EntreeInventaire(
                date: $0.date,
                domaine: .resucrage(preventif: $0.intention != .correctifHypo)
            )
        }

        let glycemies = (try? contexte.fetchCount(FetchDescriptor<GlucoseReading>())) ?? 0

        return CalculInventaireDonnees.analyser(entrees: entrees, nombreGlycemies: glycemies)
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Hub peuplé") {
    NavigationStack {
        PageInventaireDonnees()
    }
    .modelContainer(AppTabVues.conteneurApercuComplet)
}

#Preview("Hub vide") {
    NavigationStack {
        PageInventaireDonnees()
    }
    .modelContainer(for: [Repas.self, Injection.self, ActiviteSportive.self, Resucrage.self, GlucoseReading.self], inMemory: true)
}
#endif
