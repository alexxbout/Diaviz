//
//  DetailScoreVue.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import SwiftUI

/// Page de détail du score de gestion — push depuis l'accueil
/// (`CarteScoreQuotidien`) ou depuis le bouton « Voir les détails » de
/// `SheetScoreMatin`.
///
/// Décompose le score quotidien en ses 4 zones GRI (Klonoff 2022),
/// affiche un message narratif (Foundation Models, même pipeline que
/// la sheet du matin), et permet de consulter les scores des
/// 30 derniers jours par sélection de barre semaine.
///
/// Architecture :
///   - `NavigationStack` parent porte le titre `.inline` et le bouton
///     retour natif.
///   - Une seule page : tout le contenu (en-tête, barres semaine,
///     LLM, barre AGP, décompo, à propos) est piloté par l'état
///     `jourConsulte`.
///   - Les barres semaine sont **fixes** (Lundi → Dimanche) ; tap
///     sur une barre = changement de jour consulté (les barres ne
///     bougent pas, seule la mise en avant se déplace). Les boutons
///     ⟨ / ⟩ font glisser la semaine entière (avec spring).
///
/// Aucun texte ne suggère une action de soin — observations seulement.
struct DetailScoreVue: View {

    /// Jour initial à afficher au push. Typiquement « hier » (le score
    /// le plus récent disponible) ; peut être surchargé pour ouvrir
    /// directement sur un jour donné.
    let jourInitial: Date

    /// Service mocké — sera remplacé par le vrai backend quand la
    /// couche d'analyses sera branchée.
    private let service = ScoreJournalierServiceMock.shared

    /// Jour dont les métriques sont affichées (cercle, message LLM,
    /// barre AGP, décomposition). Mis à jour par tap sur une barre
    /// ou par la navigation hebdomadaire. Le `.onAppear` le recale
    /// sur le jour navigable le plus proche de `jourInitial` au
    /// premier affichage — utile si on pousse une date hors plage
    /// (futur, ou > J-30).
    @State private var jourConsulte: Date

    init(jourInitial: Date) {
        self.jourInitial = jourInitial
        self._jourConsulte = State(initialValue: jourInitial)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
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
        .navigationTitle("Score de gestion")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Recale `jourConsulte` sur le jour navigable le plus
            // proche de `jourInitial` (cas où l'appelant pousse une
            // date hors plage).
            jourConsulte = jourPlusProche(de: jourInitial)
        }
    }

    // MARK: Données dérivées

    /// Score du jour consulté. Cas particulier pour aujourd'hui : on
    /// retourne le `partielDuJour` (assemblé à partir du score en cours)
    /// plutôt que de chercher dans la liste consolidée — la journée
    /// n'est pas clôturée à 06h donc elle n'y figure pas.
    private var scoreCourant: ScoreJournalier? {
        if calendrierFrancais.isDate(jourConsulte, inSameDayAs: Date()) {
            return service.partielDuJour
        }
        return service.score(pour: jourConsulte)
    }

    /// Est-on en train de consulter aujourd'hui (journée pas encore
    /// clôturée à 06h) ?
    private var estJourEnCours: Bool {
        calendrierFrancais.isDate(jourConsulte, inSameDayAs: Date())
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
        if cal.isDate(cibleStart, inSameDayAs: Date()) {
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
                        CercleScoreDetail(score: scoreCourant?.score)
                            .frame(width: 88, height: 88)

                        Text(libelleQualitatif)
                            .font(.headline.bold())
                            .foregroundStyle(.primary)
                            .frame(maxWidth: 100)
                            .multilineTextAlignment(.center)
                            .contentTransition(.numericText())
                    }

                    BarresSemaine(
                        jourConsulte: jourConsulte,
                        scorePourJour: { jour in
                            // Aujourd'hui n'est pas dans la liste
                            // consolidée — on lit le score partiel
                            // calculé en temps réel.
                            if calendrierFrancais.isDate(jour, inSameDayAs: Date()) {
                                return service.scoreDuJour
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

                messageLLM
                    .padding(.top, 4)
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
    /// (`SheetScoreMatin`, `CarteScoreQuotidien`).
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

    /// Texte narratif Foundation Models (même pipeline que la sheet du
    /// matin). Trois branches :
    ///   - **Jour en cours** : pas de résumé LLM (la journée n'est pas
    ///     clôturée), juste un message neutre "Journée en cours · Xh
    ///     de données" — pas de disclaimer IA car pas d'IA invoquée.
    ///   - **Jour clôturé avec faits** : pipeline LLM standard.
    ///   - **Aucun fait disponible** (cas dégénéré, edge backend) :
    ///     texte court de repli.
    @ViewBuilder
    private var messageLLM: some View {
        if estJourEnCours {
            Text("Journée en cours · \(heuresDataDuJour)h de données")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if let faits = scoreCourant?.faits {
            MessageNarratifScore(faits: faits)
        } else {
            Text("Pas de résumé disponible pour ce jour.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    /// Heures écoulées depuis 06h ce matin (arrondi inférieur) — utilisé
    /// par le message "Journée en cours · Xh de données".
    private var heuresDataDuJour: Int {
        Int(service.heuresDataDuJour.rounded(.down))
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
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

// MARK: - Cercle gradient 100pt

/// Cercle 100pt portant le score en blanc — réutilise `MeshScore` (le
/// mesh gradient partagé du module score) et la teinte continue
/// `CouleurScore.couleur(pour:)` pour l'ombre. Calqué sur le cercle de
/// `SheetScoreMatin` mais à la taille spec'd pour la page détail (100pt).
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

// MARK: - Barres semaine fixes (lundi → dimanche)

/// Composant « semaine » de la page détail :
///   - 7 barres verticales représentant lundi → dimanche de la
///     **semaine contenant** `jourConsulte`. Les barres sont
///     **toujours en position fixe** ; seule la mise en avant
///     (bordure 2pt) se déplace selon `jourConsulte`.
///   - Labels « L M M J V S D » sous les barres.
///
/// Tap sur une barre → `onChangerJour(jour)` (les barres restent en
/// place — c'est la sélection du jour consulté qui bouge). La
/// navigation est restreinte à la semaine de `jourInitial` ;
/// l'utilisateur ne peut pas consulter les semaines précédentes (choix
/// produit : on évite de mettre en exergue des scores historiques).
///
/// Si une journée de la semaine n'a pas de score (futur, ou jour
/// pour lequel le calcul n'a pas encore été fait), sa barre est
/// rendue en gris vide et le tap est ignoré.
private struct BarresSemaine: View {

    let jourConsulte: Date
    /// Closure de lecture des données — laissée non-Sendable car
    /// invoquée uniquement depuis le main actor de la vue.
    let scorePourJour: (Date) -> Int?
    let onChangerJour: (Date) -> Void

    private static let hauteurBarres: CGFloat = 72
    private static let largeurBarre: CGFloat = 24
    private static let espacement: CGFloat = 8

    var body: some View {
        VStack(spacing: 10) {
            barresVue
            labelsJours
        }
    }

    // MARK: Barres (7 jours, position fixe)

    private var lundiSemaine: Date {
        lundiDeLaSemaine(jourConsulte)
    }

    private var joursSemaine: [Date] {
        let cal = calendrierFrancais
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: lundiSemaine) }
    }

    private var barresVue: some View {
        HStack(alignment: .bottom, spacing: Self.espacement) {
            ForEach(Array(joursSemaine.enumerated()), id: \.offset) { (_, jour) in
                barreJour(jour: jour, score: scorePourJour(jour))
            }
        }
        .frame(height: Self.hauteurBarres)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func barreJour(jour: Date, score: Int?) -> some View {
        let estActif = calendrierFrancais.isDate(jour, inSameDayAs: jourConsulte)
        let estJourEnCours = calendrierFrancais.isDateInToday(jour)
        let estVide = (score == nil)

        ZStack(alignment: .bottom) {
            // Track gris en fond pour matérialiser la hauteur max — sans
            // ça, un score à 5 / 10 « disparaît » presque, et une barre
            // vide n'a aucune présence visuelle.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(estVide ? 0.08 : 0.12))
                .frame(width: Self.largeurBarre, height: Self.hauteurBarres)

            if let score {
                let couleur = CouleurScore.couleur(pour: score)
                if estJourEnCours {
                    // Jour en cours — barre **hachurée** (stripes
                    // diagonales 45°) sur un fond légèrement teinté.
                    // Le motif hachuré est universellement reconnu
                    // comme "en construction / pas définitif" — bien
                    // plus visible qu'un simple remplissage dilué, et
                    // sans besoin d'animation (la page détail doit
                    // rester calme, contrairement à l'accueil).
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(couleur.opacity(0.18))
                        HachureDiagonale(couleur: couleur)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(width: Self.largeurBarre, height: hauteurBarre(score: score))
                } else {
                    // Jour clôturé — barre pleine, opaque.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(couleur)
                        .frame(width: Self.largeurBarre, height: hauteurBarre(score: score))
                }
            }

            // Bordure de mise en avant sur le jour consulté — posée
            // sur tout le track (pleine hauteur) pour matérialiser la
            // sélection même quand le score est faible.
            if estActif {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                    .frame(width: Self.largeurBarre, height: Self.hauteurBarres)
            }
        }
        .frame(width: Self.largeurBarre, height: Self.hauteurBarres, alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            // Pas de saut sur une barre vide : tap silencieusement
            // ignoré (pas d'animation, pas de changement d'état).
            guard !estVide else { return }
            onChangerJour(jour)
        }
        .accessibilityElement()
        .accessibilityLabel(libelleAccessibilite(jour: jour, score: score, estActif: estActif))
        .accessibilityAddTraits(estVide ? [] : .isButton)
    }

    private func hauteurBarre(score: Int) -> CGFloat {
        let ratio = max(0.05, min(1.0, Double(score) / 100.0))
        return Self.hauteurBarres * ratio
    }

    // MARK: Labels (L M M J V S D)

    private var labelsJours: some View {
        HStack(spacing: Self.espacement) {
            ForEach(Array(joursSemaine.enumerated()), id: \.offset) { (_, jour) in
                Text(initialeJour(jour))
                    .font(.caption2)
                    .foregroundStyle(estJourConsulte(jour) ? .primary : .secondary)
                    .fontWeight(estJourConsulte(jour) ? .semibold : .regular)
                    .frame(width: Self.largeurBarre)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func estJourConsulte(_ jour: Date) -> Bool {
        calendrierFrancais.isDate(jour, inSameDayAs: jourConsulte)
    }

    /// Initiale française du jour de la semaine. Calendrier forcé en
    /// lundi-premier pour rester cohérent avec l'ordre des barres.
    private func initialeJour(_ jour: Date) -> String {
        let cal = calendrierFrancais
        let weekday = cal.component(.weekday, from: jour) // 1=dim, 2=lun, ..., 7=sam
        let initiales = ["D", "L", "M", "M", "J", "V", "S"]
        return initiales[(weekday - 1 + 7) % 7]
    }

    // MARK: Accessibilité

    private func libelleAccessibilite(jour: Date, score: Int?, estActif: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        let dateStr = formatter.string(from: jour).capitalizedFirst
        guard let score else {
            return "\(dateStr), pas de données disponibles"
        }
        if estActif {
            return "\(dateStr), score \(score) sur 100, jour consulté"
        }
        return "\(dateStr), score \(score) sur 100, toucher pour consulter ce jour"
    }
}

// MARK: - Motif hachuré (jour en cours)

/// Stripes diagonales à 45° dessinées via `Canvas` — utilisé pour
/// remplir la barre du jour en cours dans `BarresSemaine` sans avoir
/// recours à une animation ou à une opacité globale qui rend la barre
/// peu lisible.
///
/// Les lignes vont du coin haut-gauche au coin bas-droit (orientation
/// "descendante" — la convention la plus courante pour signaler une
/// zone en travaux ou en attente). Le pas (`espacement + largeurTrait`)
/// reste constant : le motif a la même densité quelle que soit la
/// hauteur de la barre.
///
/// Le clipping aux coins arrondis est fait par le parent
/// (`.clipShape(RoundedRectangle…)`), pas ici — `HachureDiagonale`
/// remplit naturellement son cadre rectangulaire.
private struct HachureDiagonale: View {

    let couleur: Color
    var espacement: CGFloat = 4
    var largeurTrait: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let pas = espacement + largeurTrait
            // `c` est l'abscisse au point haut de chaque ligne. On
            // sweep de 0 à `size.width + size.height` pour couvrir
            // tout le rectangle : aux extrémités, la ligne déborde
            // hors du cadre — c'est le clipping du parent qui ramène
            // dans la forme arrondie.
            var c: CGFloat = 0
            while c <= size.width + size.height {
                var trace = Path()
                trace.move(to: CGPoint(x: c, y: 0))
                trace.addLine(to: CGPoint(x: c - size.height, y: size.height))
                context.stroke(
                    trace,
                    with: .color(couleur),
                    lineWidth: largeurTrait
                )
                c += pas
            }
        }
    }
}

// MARK: - Barre AGP segmentée

/// Barre horizontale segmentée pleine largeur — résume la répartition
/// du temps sur 24 h dans **3 zones glycémiques agrégées** :
///
///   - Hypo (rouge #E24B4A) — somme `tbrLevel2 + tbrLevel1` (< 70 mg/dL)
///   - En cible (vert #1D9E75) — `tir` (70–180 mg/dL)
///   - Hyper (orange #EF9F27) — somme `tarLevel1 + tarLevel2` (> 180 mg/dL)
///
/// Le détail à 5 zones (sévère / non-sévère) reste consultable dans
/// la section DÉCOMPOSITION juste en dessous — ici on agrège pour un
/// résumé lisible d'un coup d'œil.
///
/// Largeur de chaque segment proportionnelle à son pourcentage. Le
/// pourcentage est rendu en blanc centré dans le segment, à une taille
/// qui s'adapte à la largeur disponible :
///   - ≥ 15 % → `.caption` bold (largement lisible)
///   - 5–14 % → `.caption2` (compact mais lisible)
///   - < 5 % → pas de texte (sinon illisible), segment rendu en trait fin
///
/// Les coins de la barre sont arrondis via un `clipShape` global
/// (8 pt) — les segments individuels ne sont pas arrondis, c'est le
/// clip qui dessine les arrondis aux extrémités.
private struct BarreAGP: View {

    let faits: FaitsJour

    private static let hauteur: CGFloat = 32
    private static let coinArrondi: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let segments = construireSegments(largeurTotale: geo.size.width)
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { (_, seg) in
                    SegmentAGPVue(segment: seg)
                }
            }
        }
        .frame(height: Self.hauteur)
        .clipShape(RoundedRectangle(cornerRadius: Self.coinArrondi, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(libelleAccessibilite)
    }

    /// Construit les 3 segments agrégés (hypo / cible / hyper) en
    /// répartissant la largeur disponible au prorata des pourcentages.
    ///
    /// Normalisation par la somme réelle plutôt que par 100 fixe : si
    /// le mock totalise 99.5 (à cause des arrondis de génération), la
    /// barre remplit quand même toute la largeur — sans cette
    /// normalisation un mince espace blanc apparaîtrait à droite.
    private func construireSegments(largeurTotale: CGFloat) -> [SegmentAGP] {
        let pctHypo = faits.tbrLevel2 + faits.tbrLevel1
        let pctCible = faits.tir
        let pctHyper = faits.tarLevel1 + faits.tarLevel2

        let total = pctHypo + pctCible + pctHyper
        let denominateur = max(total, 0.0001) // anti-div0 sur cas dégénéré
        func largeur(_ pct: Double) -> CGFloat {
            largeurTotale * CGFloat(pct / denominateur)
        }

        // Couleurs système iOS — alignées sur celles utilisées par la
        // section DÉCOMPOSITION juste en dessous (`.red` pour la row
        // Hypo, `.green` pour Temps en cible, `.orange` pour Hyper).
        // Apple les a calibrées pour fonctionner ensemble : même
        // niveau de vivacité, accessibilité Dynamic Color (mode clair
        // / sombre, contraste élevé) gérée automatiquement.
        return [
            SegmentAGP(
                pourcent: pctHypo,
                couleur: .red,
                largeur: largeur(pctHypo),
                titre: "Hypo"
            ),
            SegmentAGP(
                pourcent: pctCible,
                couleur: .green,
                largeur: largeur(pctCible),
                titre: "En cible"
            ),
            SegmentAGP(
                pourcent: pctHyper,
                couleur: .orange,
                largeur: largeur(pctHyper),
                titre: "Hyper"
            ),
        ]
    }

    private var libelleAccessibilite: String {
        let pctHypo = faits.tbrLevel2 + faits.tbrLevel1
        let pctHyper = faits.tarLevel1 + faits.tarLevel2
        let lignes: [(String, Double)] = [
            ("Hypo", pctHypo),
            ("En cible", faits.tir),
            ("Hyper", pctHyper),
        ]
        return lignes
            .map { String(format: "%@ %.0f pour cent", $0.0, $0.1) }
            .joined(separator: ", ")
    }
}

/// Modèle interne d'un segment de la barre AGP.
private struct SegmentAGP {
    let pourcent: Double
    let couleur: Color
    let largeur: CGFloat
    let titre: String
}

/// Vue d'un segment : remplissage couleur + label « XX % » blanc centré
/// dont la taille de police s'adapte au poids du segment (voir
/// `BarreAGP` pour les seuils). En deçà de 5 %, pas de texte du tout —
/// un trait fin coloré reste visible grâce à la couleur de fond.
private struct SegmentAGPVue: View {
    let segment: SegmentAGP

    var body: some View {
        ZStack {
            segment.couleur
            if let police = policeTexte {
                Text(String(format: "%.0f %%", segment.pourcent))
                    .font(police)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
        .frame(width: max(0, segment.largeur))
    }

    /// Mapping pourcentage → font, ou `nil` si le segment est trop
    /// petit pour rendre du texte lisible. Calé sur les seuils
    /// spec'd : ≥ 15 → caption bold, 5–14 → caption2, < 5 → rien.
    private var policeTexte: Font? {
        switch segment.pourcent {
        case 15...:        return .caption.bold()
        case 5..<15:       return .caption2
        default:           return nil
        }
    }
}

// MARK: - Message narratif (LLM)

/// Encapsule la génération Foundation Models pour ce jour. Même
/// pipeline que `SheetScoreMatin` (`NarrationViewModel`), avec le
/// même rendu sobre — texte `.body .secondary` + disclaimer IA en
/// `.caption .tertiary` italique.
private struct MessageNarratifScore: View {

    let faits: FaitsJour

    @State private var modele = NarrationViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                LoaderTroisPoints()
                    .opacity(estChargement ? 1 : 0)

                Text(texteAffiche)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(estChargement ? 0 : 1)
            }
            .animation(.easeOut(duration: 0.4), value: estChargement)

            if afficherDisclaimerIA {
                Text("Contenu généré par IA, à vérifier.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: faits) {
            await modele.demarrer(faits: faits)
        }
    }

    private var estChargement: Bool {
        if case .chargement = modele.etat { return true }
        return false
    }

    private var afficherDisclaimerIA: Bool {
        switch modele.etat {
        case .streaming, .termine: return true
        case .chargement, .fallback: return false
        }
    }

    private var texteAffiche: String {
        switch modele.etat {
        case .chargement:        return ""
        case .streaming(let s):  return phraseConcatenee(s)
        case .termine(let s):    return phraseConcatenee(s)
        case .fallback(let t):   return t
        }
    }

    /// Mêmes règles de séparation que `SheetScoreMatin` — filet de
    /// sécurité si le LLM oublie les espaces entre segments.
    private func phraseConcatenee(_ segments: [SegmentNarration]) -> String {
        var resultat = ""
        var precedent: SegmentNarration?
        for segment in segments {
            if besoinSeparateur(precedent: precedent, suivant: segment) {
                resultat.append(" ")
            }
            resultat.append(segment.text)
            precedent = segment
        }
        return resultat
    }

    private func besoinSeparateur(
        precedent: SegmentNarration?,
        suivant: SegmentNarration
    ) -> Bool {
        guard let precedent else { return false }
        guard let dernierCar = precedent.text.last,
              let premierCar = suivant.text.first else { return false }
        if dernierCar.isWhitespace || premierCar.isWhitespace { return false }
        if ",.;:!?)»".contains(premierCar) { return false }
        if "(«".contains(dernierCar) { return false }
        return true
    }
}

// MARK: - Row de décomposition GRI

/// Modèle d'une row de la section décomposition.
private struct LigneGRI {
    let titre: String
    let description: String
    let pourcent: Double
    let objectifClinique: String
    let couleur: Color
    let icone: String
}

/// Row standard de la section décomposition — icône colorée à gauche,
/// libellé + barre de progression + objectif clinique au milieu,
/// pourcentage + durée à droite.
///
/// `miseEnAvant` active le style « Time in Range » : font légèrement
/// plus appuyée sur les chiffres, padding interne un peu plus généreux.
private struct LigneDecompositionGRI: View {

    let ligne: LigneGRI
    var miseEnAvant: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconeColoree

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ligne.titre)
                        .font(miseEnAvant ? .body.weight(.semibold) : .body)
                        .foregroundStyle(.primary)
                    Text(ligne.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                progressionBar

                Text("Objectif : \(ligne.objectifClinique)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPourcent(ligne.pourcent))
                    .font(miseEnAvant
                          ? .body.weight(.bold).monospacedDigit()
                          : .body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(formatDuree(ligne.pourcent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, miseEnAvant ? 10 : 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ligne.titre) \(ligne.description) : \(formatPourcent(ligne.pourcent)), \(formatDuree(ligne.pourcent)). Objectif \(ligne.objectifClinique)"
        )
    }

    private var iconeColoree: some View {
        ZStack {
            Circle()
                .fill(ligne.couleur.opacity(0.18))
            Image(systemName: ligne.icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ligne.couleur)
        }
        .frame(width: 32, height: 32)
    }

    /// Barre de progression horizontale — pleine à 100 % du
    /// `pourcent`. Plafonnée à 100 % de largeur même si la valeur
    /// dépasse l'objectif (cas rare pour le TIR ; jamais pour les
    /// 4 zones hors-cible).
    private var progressionBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(ligne.couleur)
                    .frame(width: geo.size.width * CGFloat(min(1.0, max(0, ligne.pourcent) / 100.0)))
            }
        }
        .frame(height: 6)
    }

    private func formatPourcent(_ valeur: Double) -> String {
        if valeur >= 10 || valeur == floor(valeur) {
            return String(format: "%.0f %%", valeur)
        }
        return String(format: "%.1f %%", valeur)
    }

    /// Convertit un pourcentage de journée en durée lisible :
    ///   - < 60 min → "12 min"
    ///   - ≥ 60 min → "4h19" (sans espace, format compact)
    private func formatDuree(_ pourcent: Double) -> String {
        let totalSec = ScoreJournalier.duree(pourPourcent: pourcent)
        let totalMin = Int(totalSec / 60)
        if totalMin < 60 {
            return "\(totalMin) min"
        }
        let h = totalMin / 60
        let m = totalMin % 60
        if m == 0 { return "\(h) h" }
        return String(format: "%dh%02d", h, m)
    }
}

// MARK: - Loader

/// Trois points qui pulsent — affichés pendant la génération LLM.
/// Local à ce fichier (même esprit que `LoaderPoints` de
/// `SheetScoreMatin`, mais privé ici pour éviter les couplages
/// inter-fichiers d'utilitaires d'affichage).
private struct LoaderTroisPoints: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(0.5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TimelineView(.periodic(from: .now, by: 0.4)) { contexte in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.secondary)
                            .frame(width: 8, height: 8)
                            .opacity(opacite(index: index, date: contexte.date))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func opacite(index: Int, date: Date) -> Double {
        let bucket = Int(date.timeIntervalSince1970 / 0.4) % 3
        return bucket == index ? 1.0 : 0.3
    }
}

// MARK: - Helpers calendaires

/// Calendrier grégorien forcé en lundi-premier — utilisé partout dans
/// cette page pour ne pas dépendre des préférences système (US =
/// dimanche premier). File-private pour rester local au module score.
private var calendrierFrancais: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2 // 1=dimanche, 2=lundi
    cal.locale = Locale(identifier: "fr_FR")
    return cal
}

/// Lundi 00:00 (locale) de la semaine contenant `jour`. Le calcul se
/// fait sur `startOfDay(jour)` pour éviter les sauts si `jour` tombe
/// pile à minuit (heure légale).
private func lundiDeLaSemaine(_ jour: Date) -> Date {
    let cal = calendrierFrancais
    let weekday = cal.component(.weekday, from: jour) // 1=dim, 2=lun, ..., 7=sam
    let offsetVersLundi = (weekday + 5) % 7 // lun=0, mar=1, ..., dim=6
    let debutJour = cal.startOfDay(for: jour)
    return cal.date(byAdding: .day, value: -offsetVersLundi, to: debutJour) ?? debutJour
}

private extension String {
    /// Met en majuscule la première lettre — utilisé pour les jours
    /// français qui ressortent en minuscules de `DateFormatter`.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Previews

#Preview("Très bonne — 92") {
    NavigationStack {
        DetailScoreVue(jourInitial: _previewJourScore(92) ?? Date())
    }
}

#Preview("Bonne — 76") {
    NavigationStack {
        DetailScoreVue(jourInitial: _previewJourScore(76) ?? Date())
    }
}

#Preview("Difficile — 42") {
    NavigationStack {
        DetailScoreVue(jourInitial: _previewJourScore(42) ?? Date())
    }
}

/// Cherche un jour dans le mock dont le score est le plus proche de
/// `cible`. Permet aux previews d'ouvrir directement sur un palier
/// donné sans hardcoder un index — robuste si on retouche la liste.
@MainActor
private func _previewJourScore(_ cible: Int) -> Date? {
    let service = ScoreJournalierServiceMock.shared
    return service.scores
        .min(by: { abs($0.score - cible) < abs($1.score - cible) })?
        .jour
}
