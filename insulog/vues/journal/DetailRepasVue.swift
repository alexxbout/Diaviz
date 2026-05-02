//
//  DetailRepasVue.swift
//  insulog
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

// MARK: - DetailRepasVue
//
// Page de détail d'un repas, pushée depuis la `LigneRepasJournal` via un
// `NavigationLink`. Architecture en 5 sections empilées dans un `ScrollView` :
//
// 1. **En-tête contextuel** — nom du repas + date relative
// 2. **Graphique élargi** — `GraphiqueGlycemiqueRepas` (220pt, dans une card)
// 3. **Métriques** — pic, retour en cible, TIR post-prandial
// 4. **Aliments** — liste en lecture seule
// 5. **Récap injection** — total insuline, glucides, ratio, site
//
// Le menu ⋯ en topBarTrailing ouvre Modifier (sheet d'édition) ou Supprimer
// (alerte de confirmation puis pop du `NavigationStack`).
struct DetailRepasVue: View {

    // MARK: - Paramètres

    let repas: Repas
    /// Titre de la section parente (« Petit-déjeuner », « Déjeuner »…) —
    /// le `Repas` lui-même ne porte pas de libellé, on le reçoit du
    /// contexte d'origine pour pouvoir le présenter en nav bar et en
    /// en-tête de page.
    let titreSection: String

    /// Callback de suppression — appelé après confirmation de l'alerte.
    /// Optionnel : si `nil`, on se contente de pop le `NavigationStack`
    /// (pratique pour les previews qui n'ont pas de service à invoquer).
    var onSupprimer: (() -> Void)? = nil

    /// Callback d'édition — déclenché par le menu « Modifier ». Comme
    /// la sheet d'édition complète d'un repas n'est pas isolable du
    /// flow d'`AjouterRepasVue`, on délègue au parent.
    var onModifier: (() -> Void)? = nil

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local

    @State private var afficherConfirmationSuppression = false

    // MARK: - Corps

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                sectionEntete
                cardGraphique
                // Section IOB juste sous le graphique : pour un repas
                // pris alors qu'un bolus précédent est encore en train
                // d'agir, le risque de surdosage est immédiat — l'info
                // doit être lue avant les métriques détaillées.
                sectionInsulineActive
                sectionMetriques
                sectionAliments
                sectionInjection
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(titreSection)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { menuActions }
        .alert(
            "Supprimer ce repas ?",
            isPresented: $afficherConfirmationSuppression
        ) {
            Button("Supprimer", role: .destructive) { confirmerSuppression() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action est irréversible.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var menuActions: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    onModifier?()
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    afficherConfirmationSuppression = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Actions sur le repas")
            }
        }
    }

    // MARK: - Section 1 — En-tête contextuel
    //
    // Titre du repas en `.title2.bold()` + date relative française
    // (« Aujourd'hui à 7h30 ») sur deux lignes. Aligné à gauche avec
    // le même padding horizontal que les autres sections.

    private var sectionEntete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titreSection)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(dateRelativeFormatee)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    /// Date au format « Aujourd'hui à 7h30 » / « Hier à 12h15 » /
    /// « Jeudi 30 avr. à 19h00 » selon la proximité avec aujourd'hui.
    /// Utilise systématiquement la locale `fr_FR` — sinon le formatter
    /// par défaut suit la locale système et peut produire « Thursday
    /// 30 Apr at 7:30 AM ». L'heure est forcée au format « 7h30 »
    /// (notation française usuelle, plus lisible que « 07:30 »).
    private var dateRelativeFormatee: String {
        let cal = Calendar.current
        let jourTexte: String
        if cal.isDateInToday(repas.heure) {
            jourTexte = "Aujourd'hui"
        } else if cal.isDateInYesterday(repas.heure) {
            jourTexte = "Hier"
        } else {
            // « jeudi 30 avr. » → on capitalise la première lettre pour
            // une lecture en début de phrase : « Jeudi 30 avr. à 18h45 ».
            jourTexte = Self.formatterDateLongue
                .string(from: repas.heure)
                .capitalizedFirstLetter
        }
        let heureTexte = Self.formatterHeure.string(from: repas.heure)
        return "\(jourTexte) à \(heureTexte)"
    }

    /// Formatter du jour long — « jeudi 30 avr. » en français. Locale
    /// française fixe pour ne pas dépendre du device.
    private static let formatterDateLongue: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMM"
        return f
    }()

    /// Formatter de l'heure — « 7h30 », « 18h45 ». Pattern `H'h'mm` :
    /// `H` (heure 0-23), `'h'` littéral, `mm` (minutes zéro-paddées).
    private static let formatterHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "H'h'mm"
        return f
    }()

    // MARK: - Section 2 — Card graphique
    //
    // Card pleine largeur avec fond `secondarySystemGroupedBackground`,
    // cornerRadius 16, padding interne 16, margin externe 16. Le composant
    // `GraphiqueGlycemiqueRepas` gère lui-même les états dégradés.

    private var cardGraphique: some View {
        GraphiqueGlycemique.pourRepas(etat: etatAnalyseEffectif)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 16)
    }

    /// Étatde l'analyse — fallback sur `donneesManquantes` si le repas
    /// n'a pas de réponse pré-calculée (cas legacy).
    private var etatAnalyseEffectif: EtatAnalyse {
        repas.etatAnalyse ?? .donneesManquantes
    }

    // MARK: - Section 2bis — Insuline active au démarrage du repas
    //
    // Card de mise en évidence de l'IOB. Délégué à `BadgeIOB` —
    // composant partagé avec `DetailActiviteVue` pour qu'une évolution
    // des seuils ou du visuel se propage automatiquement aux deux
    // pages.
    //
    // `sectionOptionnelle` s'efface complètement quand l'IOB est nul
    // ou inconnu — pas de placeholder, on n'occupe pas l'écran avec
    // une info non actionnable.

    private var sectionInsulineActive: some View {
        BadgeIOB.sectionOptionnelle(iob: repas.iobAuDebut)
    }

    // MARK: - Section 3 — Métriques glycémiques
    //
    // Affichée uniquement si une réponse glycémique est disponible.
    // Trois lignes (pic, retour en cible, TIR) au format « libellé à
    // gauche, valeur à droite en bold ». Style `Form.grouped` sans header
    // pour la cohérence visuelle avec les autres sections.

    @ViewBuilder
    private var sectionMetriques: some View {
        if case .disponible(let reponse) = etatAnalyseEffectif {
            CarteRegroupee {
                LigneMetrique(
                    libelle: "Pic glycémique",
                    valeur: "\(Int(reponse.valeurPic)) mg/dL",
                    sousValeur: "À \(formaterTemps(reponse.tempsPic))"
                )
                Divider().padding(.leading, 16)
                LigneMetrique(
                    libelle: "Retour en cible",
                    valeur: reponse.tempsRetourCible.map { formaterTemps($0) } ?? "—",
                    sousValeur: nil
                )
                Divider().padding(.leading, 16)
                LigneMetrique(
                    libelle: "TIR post-prandial",
                    valeur: tirPostPrandial(reponse: reponse),
                    sousValeur: nil
                )
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Section 4 — Aliments
    //
    // Header « ALIMENTS » en `.caption.bold()` aligné iOS Form. Liste des
    // aliments du repas via `CarteAliment` (composant existant utilisé
    // déjà dans `ListeRepasParSection`). En lecture seule — pas de swipe ici,
    // l'édition se fait via le menu ⋯ → Modifier.

    private var sectionAliments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALIMENTS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            CarteRegroupee {
                ForEach(Array(repas.aliments.enumerated()), id: \.element.id) { index, aliment in
                    CarteAliment(
                        emoji: aliment.emoji,
                        nom: aliment.nom,
                        quantite: aliment.quantite,
                        glucides: aliment.glucides,
                        insuline: aliment.insuline
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if index < repas.aliments.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Section 5 — Récap injection
    //
    // Lignes : insuline totale, glucides totaux, ratio appliqué, heure,
    // site (placeholder pour l'instant — `Repas` ne stocke pas le site).
    // Affichée même quand `aUneInjection == false` pour rester structurée,
    // mais avec « — » sur les valeurs absentes.

    private var sectionInjection: some View {
        CarteRegroupee {
            LigneMetrique(
                libelle: "Insuline totale",
                valeur: formaterInsuline(repas.totalInsuline),
                sousValeur: nil
            )
            Divider().padding(.leading, 16)
            LigneMetrique(
                libelle: "Glucides totaux",
                valeur: "\(repas.totalGlucides) g",
                sousValeur: nil
            )
            Divider().padding(.leading, 16)
            LigneMetrique(
                libelle: "Ratio appliqué",
                valeur: ratioFormate,
                sousValeur: nil
            )
            Divider().padding(.leading, 16)
            LigneMetrique(
                libelle: "Heure d'injection",
                valeur: repas.heure.formatted(date: .omitted, time: .shortened),
                sousValeur: nil
            )
            Divider().padding(.leading, 16)
            LigneMetrique(
                libelle: "Site d'injection",
                valeur: "—",
                sousValeur: nil
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    /// Format compact pour un délai en secondes : « T+1h15 » / « T+45min ».
    /// Préfixé par « T+ » pour rappeler le référentiel post-prandial.
    private func formaterTemps(_ secondes: TimeInterval) -> String {
        let minutes = Int(secondes / 60)
        if minutes < 60 { return "T+\(minutes)min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "T+\(h)h" : "T+\(h)h\(m)"
    }

    /// Insuline formatée : « 5u » si entier, « 3.5u » sinon.
    private func formaterInsuline(_ dose: Double) -> String {
        if dose == 0 { return "—" }
        if dose.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(dose))u"
        }
        return String(format: "%.1fu", dose)
    }

    /// Ratio insuline-glucides « 1u/18g » — dérivé de glucides/dose.
    /// `—` si la dose est nulle (division par zéro impossible et le
    /// calcul n'a pas de sens sans bolus).
    private var ratioFormate: String {
        guard repas.totalInsuline > 0 else { return "—" }
        let gParUnite = Double(repas.totalGlucides) / repas.totalInsuline
        return String(format: "1u/%.0fg", gParUnite)
    }

    /// TIR (Time In Range) post-prandial : pourcentage des échantillons
    /// CGM compris entre 70 et 180 mg/dL sur la fenêtre T0 → T+4h. Calculé
    /// localement parce qu'il n'est pas pré-stocké dans `ReponseGlycemique`.
    private func tirPostPrandial(reponse: ReponseGlycemique) -> String {
        let postRepas = reponse.pointsCgm.filter { $0.secondesDepuisRepas >= 0 }
        guard !postRepas.isEmpty else { return "—" }
        let dansCible = postRepas.filter { $0.valeur >= 70 && $0.valeur <= 180 }
        let pct = Int(round(Double(dansCible.count) / Double(postRepas.count) * 100))
        return "\(pct)%"
    }

    // MARK: - Actions

    private func confirmerSuppression() {
        if let onSupprimer {
            onSupprimer()
        }
        dismiss()
    }
}

// MARK: - String helper
//
// Capitalise uniquement la première lettre — `String.capitalized`
// capitalise CHAQUE mot et transformerait « jeudi 30 avr. » en
// « Jeudi 30 Avr. ». Ici on veut juste la majuscule en tête de phrase.
private extension String {
    var capitalizedFirstLetter: String {
        guard let premiere = first else { return self }
        return String(premiere).uppercased() + dropFirst()
    }
}

// MARK: - Mocks pour previews
//
// Le modèle `Repas` n'a pas d'helper de mock dédié — on crée ici quelques
// instances pré-cuisinées pour exercer les trois variantes principales
// de la page (analyse OK, en attente, sans injection).

extension Repas {

    /// Repas standard avec analyse glycémique disponible — courbe verte
    /// (verdict « bon »). Utilisé comme cas nominal des previews. IOB
    /// nul : c'est un petit-déjeuner, premier repas de la journée.
    static var mockAvecAnalyseBonne: Repas {
        let heure = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
        return Repas(
            heure: heure,
            aliments: [
                Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
                Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
                Aliment(emoji: "🥛", nom: "Lait demi-écrémé", quantite: 200, glucides: 10, insuline: 0.5),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.bon),
            iobAuDebut: nil
        )
    }

    /// Repas trop récent — la fenêtre T+4h n'est pas encore complète.
    /// Affiche le rendu « clock.fill » à la place du graphique. IOB
    /// modéré (0.8u) : déjeuner pris alors que le bolus de la
    /// collation matinale est encore actif → exerce le rendu orange
    /// « Modéré » de la card IOB.
    static var mockEnAttente: Repas {
        let heure = Calendar.current.date(byAdding: .minute, value: -90, to: Date()) ?? Date()
        return Repas(
            heure: heure,
            aliments: [
                Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.enAttente),
            iobAuDebut: 0.8
        )
    }

    /// Repas sans bolus — pas d'analyse glycémique légitime à proposer.
    /// IOB élevé (2.2u) : prendre un en-cas sans dose alors qu'il
    /// reste 2u d'insuline active explique pourquoi le repas a été
    /// log « sans insuline » → exerce le rendu rouge « Très élevé ».
    static var mockSansInjection: Repas {
        let heure = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date()
        return Repas(
            heure: heure,
            aliments: [
                Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0.0),
                Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 0.0),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.sansInjection),
            iobAuDebut: 2.2
        )
    }
}

// MARK: - Aperçu

#Preview("Repas avec analyse") {
    NavigationStack {
        DetailRepasVue(
            repas: .mockAvecAnalyseBonne,
            titreSection: "Petit-déjeuner"
        )
    }
}

#Preview("Repas en attente") {
    NavigationStack {
        DetailRepasVue(
            repas: .mockEnAttente,
            titreSection: "Déjeuner"
        )
    }
}

#Preview("Repas sans injection") {
    NavigationStack {
        DetailRepasVue(
            repas: .mockSansInjection,
            titreSection: "En-cas"
        )
    }
}
