//
//  DetailScoreVue.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import SwiftUI
import SwiftData

/// Page de détail du score de gestion — push depuis l'accueil
/// (`CarteScoreQuotidien`).
///
/// Décompose le score quotidien en ses 4 zones GRI (Klonoff 2022) et
/// permet de consulter les scores des 7 derniers jours par sélection
/// d'une barre.
///
/// Architecture :
///   - `NavigationStack` parent porte le titre `.inline` et le bouton
///     retour natif.
///   - Une seule page : tout le contenu (en-tête, barres semaine,
///     LLM, barre AGP, décompo, à propos) est piloté par l'état
///     `jourConsulte`.
///   - Les barres montrent les **7 derniers jours glissants** (se
///     terminant au jour en cours), en position fixe ; tap sur une
///     barre = changement de jour consulté (les barres ne bougent
///     pas, seule la mise en avant se déplace).
///
/// Sous-vues extraites dans ce dossier (`Score/`) : `BarresSemaine`,
/// `BarreAGP`, `LigneDecompositionGRI`, `LoaderPoints` ; helpers
/// calendaires dans `CalendrierScore.swift`.
///
/// Aucun texte ne suggère une action de soin — observations seulement.
struct DetailScoreVue: View {

    /// Jour initial à afficher au push. Typiquement « hier » (le score
    /// le plus récent disponible) ; peut être surchargé pour ouvrir
    /// directement sur un jour donné.
    let jourInitial: Date

    /// Service réel du score — lit le hub `GlucoseReading` et calcule le GRI.
    @State private var service = ScoreService()

    /// Contexte du hub, injecté dans le service au démarrage de la vue.
    @Environment(\.modelContext) private var modelContext

    /// Jour dont les métriques sont affichées (cercle, message LLM,
    /// barre AGP, décomposition). Mis à jour par tap sur une barre
    /// ou par la navigation hebdomadaire. Le `.onAppear` le recale
    /// sur le jour navigable le plus proche de `jourInitial` au
    /// premier affichage — utile si on pousse une date hors plage
    /// (futur, ou > J-30).
    @State private var jourConsulte: Date

    /// Pilote la sheet d'empreinte glycémique — ouverte par tap sur
    /// `CercleScoreDetail` (carte Résumé).
    @State private var afficherEmpreinte = false

    init(jourInitial: Date) {
        self.jourInitial = jourInitial
        self._jourConsulte = State(initialValue: jourInitial)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
                EnTeteAnalyse(
                    surtitre: "Aujourd'hui",
                    titre: "Score du jour",
                    accroche: "100 moins votre indice de risque glycémique, pondéré par la gravité des écarts.",
                    ambiance: .score
                )
                carteResume
                carteAnalyse
                carteAPropos
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .pageAvecBandeau(titre: "Score de gestion", debordHaut: 12)
        .task {
            service.demarrer(contexte: modelContext)
            // Recale `jourConsulte` sur le jour navigable le plus proche de
            // `jourInitial` après `demarrer` (sinon `joursNavigables` est vide).
            jourConsulte = jourPlusProche(de: jourInitial)
        }
        .sheet(isPresented: $afficherEmpreinte) {
            EmpreinteGlycemiqueSheet(service: service, jourInitial: jourConsulte)
        }
    }

    // MARK: Données dérivées

    /// Score du jour consulté. Cas particulier pour aujourd'hui : on
    /// retourne le `partielDuJour` (assemblé à partir du score en cours)
    /// plutôt que de chercher dans la liste consolidée — la journée
    /// n'est pas clôturée à 06h donc elle n'y figure pas.
    private var scoreCourant: ScoreJournalier? {
        if service.estJourCourant(jourConsulte) {
            // Jour en cours : score seulement s'il est significatif (≥ 6h de
            // données), sinon nil → cercle « — » au lieu d'un faux « 0 ».
            return service.jourCourantSignificatif ? service.partielDuJour : nil
        }
        return service.score(pour: jourConsulte)
    }

    // MARK: Navigation jour

    /// Jour le plus proche de `cible` parmi la plage navigable.
    /// Aujourd'hui est traité comme navigable même s'il n'est pas dans
    /// `service.joursNavigables` (qui ne liste que les jours consolidés
    /// J-30…J-1) — la page sait afficher le score partiel en mode
    /// "journée en cours".
    private func jourPlusProche(de cible: Date) -> Date {
        let cal = calendrierFrancais
        let cibleStart = cal.startOfDay(for: cible)
        if service.estJourCourant(cibleStart) {
            return cibleStart
        }
        return service.joursNavigables.min(by: {
            abs($0.timeIntervalSince(cibleStart)) < abs($1.timeIntervalSince(cibleStart))
        }) ?? cibleStart
    }

    // MARK: - Cartes

    /// Carte 1 — Résumé : date centrée, layout horizontal cercle 100pt +
    /// barres semaine (avec navigation < > en interne), puis texte LLM
    /// narratif et disclaimer IA. Animée en `.spring` sur `jourConsulte`
    /// pour adoucir les transitions de changement de jour.
    private var carteResume: some View {
        CartePage {
            VStack(alignment: .leading, spacing: 16) {
                Text(libelleDate)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentTransition(.numericText())

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 10) {
                        Button {
                            afficherEmpreinte = true
                        } label: {
                            CercleScoreDetail(score: scoreCourant?.score)
                                .frame(width: 88, height: 88)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityHint("Ouvre l'empreinte glycémique du jour")

                        Text(libelleQualitatif)
                            .font(.headline.bold())
                            .foregroundStyle(.primary)
                            .frame(maxWidth: 100)
                            .multilineTextAlignment(.center)
                            .contentTransition(.numericText())
                    }

                    BarresSemaine(
                        jourConsulte: jourConsulte,
                        jourEnCours: service.jourCourant,
                        scorePourJour: { jour in
                            // Jour en cours : score partiel seulement s'il est
                            // significatif (sinon barre vide, pas un faux 0).
                            if service.estJourCourant(jour) {
                                return service.scoreDuJourSignificatif
                            }
                            return service.score(pour: jour)?.score
                        },
                        onChangerJour: { jourCible in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                jourConsulte = jourCible
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)
                }

            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: jourConsulte)
        }
    }

    /// Date formatée selon la proximité avec aujourd'hui :
    ///   - J-1 → « Hier · lundi 12 mai »
    ///   - autres → « Mercredi 7 mai »
    private var libelleDate: String {
        let cal = calendrierFrancais
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        let texte = formatter.string(from: jourConsulte).capitalizedFirst

        if cal.isDateInYesterday(jourConsulte) {
            return "Hier · \(texte)"
        }
        return texte
    }

    /// 5 paliers qualitatifs alignés sur le reste du module
    /// (`CarteScoreQuotidien`).
    private var libelleQualitatif: String {
        guard let score = scoreCourant?.score else { return "Indisponible" }
        switch score {
        case 90...:    return "Très bonne"
        case 70..<90:  return "Bonne"
        case 50..<70:  return "Moyenne"
        case 30..<50:  return "Difficile"
        default:       return "Très difficile"
        }
    }

    // MARK: Carte 2 — Analyse

    /// Carte 2 — Analyse : barre AGP agrégée (3 zones) en haut, divider,
    /// puis section DÉCOMPOSITION (4 rows hors-cible + row TIR mise en
    /// avant).
    private var carteAnalyse: some View {
        CartePage {
            VStack(alignment: .leading, spacing: 12) {
                Text("RÉPARTITION")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                if let faits = scoreCourant?.faits {
                    BarreAGP(faits: faits)
                }

                Divider()
                    .padding(.vertical, 8)

                Text("DÉCOMPOSITION")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                LigneDecompositionGRI(ligne: ligneTIR, miseEnAvant: true)

                VStack(spacing: 0) {
                    ForEach(Array(lignesGRI.enumerated()), id: \.offset) { (index, ligne) in
                        if index == 0 {
                            Divider().padding(.leading, 44)
                        }
                        LigneDecompositionGRI(ligne: ligne)
                        if index < lignesGRI.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: jourConsulte)
        }
    }

    /// Les 4 zones hors-cible affichées en ordre clinique (du plus
    /// préoccupant au moins).
    private var lignesGRI: [LigneGRI] {
        guard let faits = scoreCourant?.faits else { return [] }
        return [
            LigneGRI(
                titre: "Hypo sévère",
                description: "< 54 mg/dL",
                pourcent: faits.tbrLevel2,
                objectifClinique: "< 1 %",
                couleur: Color(red: 0.60, green: 0.05, blue: 0.10),
                icone: "arrow.down.to.line"
            ),
            LigneGRI(
                titre: "Hypo",
                description: "54–69 mg/dL",
                pourcent: faits.tbrLevel1,
                objectifClinique: "< 4 %",
                couleur: .red,
                icone: "arrow.down"
            ),
            LigneGRI(
                titre: "Hyper",
                description: "181–250 mg/dL",
                pourcent: faits.tarLevel1,
                objectifClinique: "< 25 %",
                couleur: .orange,
                icone: "arrow.up"
            ),
            LigneGRI(
                titre: "Hyper sévère",
                description: "> 250 mg/dL",
                pourcent: faits.tarLevel2,
                objectifClinique: "< 5 %",
                couleur: Color(red: 0.95, green: 0.40, blue: 0.10),
                icone: "arrow.up.to.line"
            ),
        ]
    }

    private var ligneTIR: LigneGRI {
        let pct = scoreCourant?.faits.tir ?? 0
        return LigneGRI(
            titre: "Temps en cible",
            description: "70–180 mg/dL",
            pourcent: pct,
            objectifClinique: "> 70 %",
            couleur: .green,
            icone: "target"
        )
    }

    // MARK: Carte 3 — À propos du score (disclosure)

    /// Carte 3 — DisclosureGroup descriptif sur le GRI. Pas de padding
    /// interne via `CartePage` ici : on laisse le DisclosureGroup gérer
    /// son propre padding pour que la zone de tap couvre toute la carte.
    private var carteAPropos: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup {
                Text(texteAPropos)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
            } label: {
                Text("À propos du score")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
    }

    /// Bloc d'explication factuel — décrit ce que le score représente
    /// sans rien recommander, conformément au principe « pas d'avis
    /// médical ». Reformulation maison du résumé Klonoff.
    private var texteAPropos: String {
        """
        Ce score est basé sur le Glycemia Risk Index (GRI), une mesure clinique standardisée publiée par Klonoff et al. (2022). Il reflète la répartition du temps passé dans les différentes zones glycémiques sur 24 heures.

        Un score élevé signifie que la majorité du temps a été passé dans la zone cible (70–180 mg/dL) avec peu d'épisodes hors cible. Un score bas indique davantage de temps en hypoglycémie ou hyperglycémie.

        Ce score est une mesure descriptive. Il ne constitue pas un avis médical et ne formule aucune recommandation thérapeutique. Pour toute décision concernant votre traitement, consultez votre médecin.
        """
    }
}

// MARK: - Conteneur de carte

/// Conteneur de carte de la page détail — fond
/// `secondarySystemGroupedBackground`, radius `Radius.medium`, padding
/// interne 20pt. Identique à `CarteRegroupee` mais avec padding intégré
/// pour les pages où chaque carte est un bloc autonome (et non un
/// agrégat de lignes pleine largeur).
private struct CartePage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCarte()
    }
}

// MARK: - Cercle gradient 100pt

/// Cercle 100pt portant le score en blanc — réutilise `MeshScore` (le
/// mesh gradient partagé du module score) et la teinte continue
/// `CouleurScore.couleur(pour:)` pour l'ombre.
private struct CercleScoreDetail: View {
    let score: Int?

    var body: some View {
        ZStack {
            TimelineView(.animation) { contexte in
                MeshScore.gradient(
                    pour: score,
                    phase: MeshScore.phase(date: contexte.date)
                )
                .clipShape(Circle())
                .shadow(
                    color: couleurOmbre.opacity(0.40),
                    radius: 10,
                    x: 0,
                    y: 5
                )
            }

            Text(score.map(String.init) ?? "—")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        }
        .accessibilityLabel(libelleAccessibilite)
    }

    private var couleurOmbre: Color {
        guard let score else { return .gray }
        return CouleurScore.couleur(pour: score)
    }

    private var libelleAccessibilite: String {
        guard let score else { return "Score indisponible" }
        return "Score \(score) sur 100"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Hier") {
    NavigationStack {
        DetailScoreVue(jourInitial: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }
    .modelContainer(ScoreService.conteneurApercu())
}

#Preview("Aujourd'hui") {
    NavigationStack {
        DetailScoreVue(jourInitial: Date())
    }
    .modelContainer(ScoreService.conteneurApercu())
}

#Preview("Hub vide") {
    NavigationStack {
        DetailScoreVue(jourInitial: Date())
    }
}
#endif
