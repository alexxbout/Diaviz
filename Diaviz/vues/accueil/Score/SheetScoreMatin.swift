//
//  SheetScoreMatin.swift
//  diaviz
//
//  Created by Alexandre on 13/05/2026.
//

import SwiftUI
import Charts

/// Sheet « Score du matin » — résumé visuel détaillé du score de la
/// veille, présentée automatiquement au lancement de l'app (cf.
/// `AppTabVues`).
///
/// Layout vertical centré : grand cercle dégradé (120pt) portant le
/// score, libellé qualitatif, date au format français long, paragraphe
/// d'analyse généré par Foundation Models en texte brut, et bouton
/// plein largeur pour fermer la sheet.
///
/// Réutilise :
///   - `MeshScore` et `CouleurScore` (cf. `CarteScoreQuotidien.swift`)
///     pour le dégradé et la teinte d'accent du cercle / bouton.
///   - `NarrationViewModel` (cf. `composants/NarrationJourVue.swift`)
///     pour piloter la génération LLM — mais rendue ici en texte
///     simple (.body .secondary), sans coloration sémantique ni emoji,
///     pour rester sobre dans le contexte de la sheet.
struct SheetScoreMatin: View {

    /// Métriques de la journée — alimentent à la fois l'affichage du
    /// score (via `faits.score`) et la génération de la phrase
    /// narrative par `NarrationViewModel`.
    let faits: FaitsJour

    /// Date affichée sous le libellé qualitatif.
    let date: Date

    /// Callback invoqué quand l'utilisateur tape « Voir les détails ».
    /// La sheet se contente de `dismiss()` et délègue la suite (push
    /// de `DetailScoreVue`) à l'appelant — typiquement `AppTabVues`
    /// qui écrit dans le binding `jourDetailScore` d'`AccueilVue`.
    ///
    /// Optionnel : si `nil`, le bouton ferme la sheet sans push (cas
    /// previews / contexte sans navigation hôte).
    var onAfficherDetails: (() -> Void)? = nil

    /// Override des 6 jours précédant `date` pour le graphique
    /// d'évolution, du plus ancien (J-6) au plus récent (J-2). Le
    /// dernier point (jour affiché) reste toujours `faits.score` pour
    /// rester cohérent avec le cercle. `nil` → on lit
    /// `ScoreJournalierServiceMock` (chemin production).
    ///
    /// Existe pour que les previews puissent piloter une courbe
    /// expressive sans dépendre des aléas du mock service.
    var historiquePrecedent: [Int?]? = nil

    /// VM partagé avec `NarrationJourVue` — même prompt, même pipeline
    /// Foundation Models. On consomme `etat` pour rendre le texte, en
    /// ignorant la coloration sémantique des segments.
    @State private var modele = NarrationViewModel()

    /// `false` pendant le premier frame d'affichage, puis bascule à
    /// `true` au `.onAppear` pour déclencher le scale-in + fondu du
    /// cercle. Une seule transition par session de sheet.
    @State private var cercleApparu = false

    /// `false` au premier frame, `true` une fois que la courbe doit
    /// apparaître. Pilote un fade-in + léger slide vers le haut sur
    /// `graphiqueEvolution`. Décale de ~200 ms après `cercleApparu`
    /// pour cascader proprement : le cercle gagne d'abord l'attention,
    /// la courbe arrive en second plan.
    @State private var graphiqueApparu = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                titre

                cercleScore
                    .padding(.top, 10)

                // Libellé qualitatif + date — bloc texte central.
                VStack(spacing: 6) {
                    Text(libelleQualitatif)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text(dateFormatee)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Mini-courbe d'évolution sur 7 jours — situe le score
                // affiché dans la tendance récente (voir `graphiqueEvolution`).
                // Fade-in + slide-up de 8pt orchestré par `graphiqueApparu`,
                // cascadé après l'animation du cercle.
                graphiqueEvolution
                    .opacity(graphiqueApparu ? 1 : 0)
                    .offset(y: graphiqueApparu ? 0 : 8)

                Divider()
                    .padding(.horizontal, 28)

                // Paragraphe d'analyse — rendu simple, sans couleur ni emoji.
                // S'étend librement en hauteur : le ScrollView parent
                // prend le relais quand le texte dépasse l'écran.
                paragrapheAnalyse
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
        // Bouton ancré en safe area bottom → toujours entièrement
        // visible sans risque de chevauchement avec la home indicator
        // ni de troncature en bas de sheet.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            boutonDetails
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .task(id: faits) {
            await modele.demarrer(faits: faits)
        }
        .task {
            // Délai avant l'animation : laisse la sheet finir de
            // glisser depuis le bas avant d'animer le cercle (sinon
            // l'animation se déclenche pendant la transition de
            // présentation et passe inaperçue). 250 ms donne le temps
            // au premier frame de poser scale 0.5 / opacity 0, puis le
            // spring se voit clairement.
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.85, dampingFraction: 0.65)) {
                cercleApparu = true
            }
            // Cascade : on attend que le cercle ait bien commencé sa
            // course (≈ 350 ms après le départ) avant de faire monter
            // la courbe. Ça évite que les deux animations s'écrasent,
            // et le regard a le temps d'enregistrer le score avant de
            // descendre sur la tendance.
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.55)) {
                graphiqueApparu = true
            }
        }
    }

    // MARK: - Sous-vues

    /// Titre de la sheet, ancré en haut. Style proche d'un titre de
    /// section iOS — `.title3.bold()` centré, padding top suffisant
    /// pour respirer sous le drag indicator (sinon le titre paraît
    /// collé au bord de la sheet).
    private var titre: some View {
        Text("Score de la veille")
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    /// Cercle 110pt avec mesh gradient continu (rouge → vert selon le
    /// score) et chiffre du score en blanc 42pt bold centré. Ombre douce
    /// dans la teinte dominante. Animations à l'apparition :
    ///   - Scale 0.5 → 1.0 avec spring (réagit à `cercleApparu`).
    ///   - Opacity 0 → 1 (même transition).
    ///   - Chiffre interpolé de 0 au score final via `ChiffreAnime`.
    private var cercleScore: some View {
        ZStack {
            TimelineView(.animation) { contexte in
                MeshScore.gradient(
                    pour: faits.score,
                    phase: MeshScore.phase(date: contexte.date)
                )
                .clipShape(Circle())
                .frame(width: 110, height: 110)
                .shadow(
                    color: couleurAccent.opacity(0.40),
                    radius: 12,
                    x: 0,
                    y: 6
                )
            }

            ChiffreAnime(cible: faits.score, duree: 1.8)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        }
        .scaleEffect(cercleApparu ? 1.0 : 0.5)
        .opacity(cercleApparu ? 1.0 : 0.0)
    }

    /// Paragraphe d'analyse — ZStack qui croise loader (visible pendant
    /// `.chargement`) et bloc texte (visible dès qu'un premier segment
    /// arrive en `.streaming`, puis stable en `.termine`). Les segments
    /// sont concaténés via `phraseConcatenee` qui rajoute les espaces
    /// manquants entre stops adjacents — le LLM les oublie parfois.
    /// Transition opacité 0.4s pour adoucir l'apparition du texte.
    ///
    /// Sous le texte généré par IA (cas `.streaming` ou `.termine`), un
    /// disclaimer en italique discret rappelle que le contenu est
    /// auto-généré et doit être vérifié — n'apparaît pas pour le
    /// fallback purement textuel ni pendant le chargement.
    private var paragrapheAnalyse: some View {
        ZStack(alignment: .top) {
            LoaderPoints()
                .opacity(estChargement ? 1 : 0)

            VStack(alignment: .leading, spacing: 14) {
                Text(texteAffiche)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if afficherDisclaimerIA {
                    Text("Contenu généré par IA, à vérifier.")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .opacity(estChargement ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.4), value: estChargement)
    }

    /// Le disclaimer n'a de sens que quand le texte vient effectivement
    /// du LLM — pas pendant le chargement ni en fallback technique
    /// (qui est une concaténation de chiffres déterministe).
    private var afficherDisclaimerIA: Bool {
        switch modele.etat {
        case .streaming, .termine: return true
        case .chargement, .fallback: return false
        }
    }

    /// `true` tant qu'aucun segment n'est encore arrivé. Bascule à
    /// `false` au premier `.streaming` non-vide.
    private var estChargement: Bool {
        if case .chargement = modele.etat { return true }
        return false
    }

    /// Texte affiché dans le paragraphe. Concatène les segments LLM (en
    /// `.streaming` ou `.termine`) avec insertion d'espaces manquants,
    /// ou retourne le fallback tel quel.
    private var texteAffiche: String {
        switch modele.etat {
        case .chargement:        return ""
        case .streaming(let s):  return phraseConcatenee(s)
        case .termine(let s):    return phraseConcatenee(s)
        case .fallback(let t):   return t
        }
    }

    /// Concatène les segments en un seul texte, en insérant un espace
    /// entre deux segments si ni la fin du précédent ni le début du
    /// suivant n'en contient déjà un — filet de sécurité car le LLM
    /// oublie parfois les espaces de séparation malgré la consigne du
    /// prompt. Mêmes règles que `NarrationJourVue.besoinSeparateur` :
    /// pas d'espace avant une ponctuation collée ni après une
    /// ouverture de parenthèse / guillemet.
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

    /// Bouton « Voir les détails » — pleine largeur, fond dans la teinte
    /// du score, coin 14pt. Ferme la sheet puis délègue à
    /// `onAfficherDetails` (push de `DetailScoreVue` par l'hôte).
    private var boutonDetails: some View {
        Button {
            dismiss()
            // Petit délai pour laisser la sheet finir sa transition
            // de fermeture avant d'enchaîner sur la push de navigation.
            // Sans ça, sur certains devices la push se déclenche
            // pendant que la sheet est encore en train de glisser,
            // et l'animation paraît saccadée.
            if let onAfficherDetails {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    onAfficherDetails()
                }
            }
        } label: {
            Text("Voir les détails")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(couleurAccent)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Évolution sur 7 jours

    /// Graphique Swift Charts montrant l'évolution du score sur les 7
    /// derniers jours menant au jour affiché (inclus). Le dernier point
    /// — celui du score présenté par la sheet — est rendu plus gros et
    /// dans la teinte du score, les 6 précédents en gris discret : on
    /// veut situer le score du jour dans la tendance, pas faire
    /// concurrence aux autres éléments visuels de la sheet.
    ///
    /// Composé de 2 marks par jour disponible :
    ///   1. **LineMark** — courbe `.catmullRom` 1.5pt en gris à 40 %,
    ///      relie les scores connus de bout en bout.
    ///   2. **PointMark** — symbol 20pt² gris pour J-6…J-2, 50pt²
    ///      coloré pour le dernier (le score qui motive la sheet).
    ///      Chaque point porte une annotation `.top` avec la valeur
    ///      numérique : `.caption2 .secondary` pour les jours passés,
    ///      `.caption2 .bold` dans la teinte du score pour le dernier.
    ///
    /// Échelle Y figée à 0–100 — les variations sont rendues
    /// proportionnelles à la pleine plage du score (un 80 occupe
    /// visuellement 80 % de la hauteur). Axe Y caché : on cherche
    /// la tendance, pas la valeur précise (les annotations donnent
    /// la valeur exacte si nécessaire). Axe X : initiale du jour
    /// en `.caption2` `.secondary`, le dernier en `.bold` pour
    /// ancrer le regard sur "ce jour-ci".
    ///
    /// Hauteur 100pt — calée pour laisser de l'air au-dessus du point
    /// le plus haut (annotation `position: .top`) sans rogner la
    /// valeur, et sous l'axe X.
    ///
    /// Trous de données : un jour à `score == nil` ne dessine aucun
    /// mark — la courbe enjambe le trou via l'interpolation entre les
    /// points adjacents. C'est volontaire : on préfère une tendance
    /// continue à un effet "puzzle" pour un graphique aussi petit.
    private var graphiqueEvolution: some View {
        let donnees = donneesGraphique
        return Chart {
            ForEach(donnees) { entree in
                if let valeur = entree.score {
                    LineMark(
                        x: .value("Jour", entree.jour, unit: .day),
                        y: .value("Score", valeur)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Jour", entree.jour, unit: .day),
                        y: .value("Score", valeur)
                    )
                    .symbolSize(entree.estDernier ? 50 : 20)
                    .foregroundStyle(
                        entree.estDernier
                            ? couleurAccent
                            : Color.secondary.opacity(0.4)
                    )
                    .annotation(position: .top, spacing: 4) {
                        Text("\(valeur)")
                            .font(.caption2)
                            .fontWeight(entree.estDernier ? .bold : .regular)
                            .foregroundStyle(
                                entree.estDernier
                                    ? couleurAccent
                                    : Color.secondary
                            )
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXAxis {
            // Une marque par jour de donnée — values explicites pour
            // garantir l'alignement label/point (sinon Charts choisit
            // ses propres tickmarks et peut décaler ou en omettre).
            AxisMarks(values: donnees.map(\.jour)) { value in
                if let jour = value.as(Date.self) {
                    AxisValueLabel(centered: true) {
                        Text(initialeJour(jour))
                            .font(.caption2)
                            .fontWeight(estJourAffiche(jour) ? .bold : .regular)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 100)
        .padding(.horizontal, 24)
        // Air supplémentaire au-dessus de la courbe : la date juste
        // au-dessus est déjà séparée par les 24pt du `VStack` parent,
        // mais avec les annotations qui posent les valeurs en haut des
        // points, on veut un peu plus de respiration visuelle.
        .padding(.top, 12)
        .accessibilityLabel("Évolution du score sur 7 jours")
        .accessibilityValue(libelleAccessibiliteCourbe)
    }

    /// Données de la courbe : 7 jours menant au jour affiché. Le
    /// dernier point est toujours `faits.score` — il doit coïncider
    /// avec le chiffre affiché dans le cercle.
    ///
    /// Source des 6 premiers points :
    ///   - `historiquePrecedent` si fourni (cas previews) ;
    ///   - sinon `ScoreJournalierServiceMock` (chemin production).
    private var donneesGraphique: [EntreeGraphique] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: date)

        // Source pour J-6…J-2 : override preview ou service mock.
        let scoresPrecedents: [Int?] = {
            if let override = historiquePrecedent {
                // Sécurise la taille à exactement 6, complète par
                // `nil` si on en reçoit moins (les previews respectent
                // la contrainte, mais on ne crash pas si elle saute).
                let pad = max(0, 6 - override.count)
                return Array(override.prefix(6)) + Array(repeating: nil, count: pad)
            }
            let historique = ScoreJournalierServiceMock.shared
                .historiqueSept(jusquA: date)
            // `historiqueSept` renvoie 7 valeurs (J-6 → jour affiché).
            // On ne garde que les 6 premières — le 7ᵉ point vient
            // toujours de `faits.score`.
            return Array(historique.prefix(6)).map(\.score)
        }()

        return (0..<7).map { offset in
            let decalage = 6 - offset
            let jour = cal.date(byAdding: .day, value: -decalage, to: base) ?? base
            let estDernier = (offset == 6)
            let score = estDernier
                ? faits.score
                : scoresPrecedents[offset]
            return EntreeGraphique(
                jour: jour,
                score: score,
                estDernier: estDernier
            )
        }
    }

    /// `true` si `jour` correspond au jour affiché par la sheet —
    /// utilisé pour mettre l'initiale du dernier label en gras.
    private func estJourAffiche(_ jour: Date) -> Bool {
        Calendar.current.isDate(jour, inSameDayAs: date)
    }

    /// Initiale du jour de la semaine en français (L, M, M, J, V, S,
    /// D). `EEEEE` = forme "narrow" du weekday — locale `fr_FR` forcée
    /// pour ne pas dépendre des préférences système.
    private func initialeJour(_ jour: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: jour)
    }

    /// Résumé textuel de la courbe pour VoiceOver — liste compacte
    /// "lundi : 78, mardi : 82, …". Les jours sans donnée sont signalés.
    private var libelleAccessibiliteCourbe: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE"
        return donneesGraphique.map { entree in
            let nom = formatter.string(from: entree.jour)
            if let v = entree.score {
                return "\(nom) : \(v)"
            }
            return "\(nom) : non disponible"
        }.joined(separator: ", ")
    }

    /// Un point du graphique d'évolution — `jour` sert d'identité,
    /// `score` à `nil` pour les jours sans donnée, `estDernier` pour
    /// distinguer visuellement le point qui correspond au score
    /// présenté par la sheet.
    private struct EntreeGraphique: Identifiable {
        let jour: Date
        let score: Int?
        let estDernier: Bool
        var id: Date { jour }
    }

    // MARK: - Helpers dérivés du score

    /// Couleur d'accent — teinte continue identique à celle utilisée par
    /// la carte d'accueil (titre, dernière barre, ombre du cercle).
    private var couleurAccent: Color {
        CouleurScore.couleur(pour: faits.score)
    }

    /// 5 paliers qualitatifs alignés sur `CarteScoreQuotidien`.
    private var libelleQualitatif: String {
        switch faits.score {
        case 90...:    return "Très bonne"
        case 70..<90:  return "Bonne"
        case 50..<70:  return "Moyenne"
        case 30..<50:  return "Difficile"
        default:       return "Très difficile"
        }
    }

    /// Date formatée en français long (ex : « samedi 13 mai 2026 »).
    /// Locale forcée à `fr_FR` pour ne pas dépendre des préférences
    /// système.
    private var dateFormatee: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Aperçus (un par palier qualitatif)

// Mocks de `FaitsJour` inline pour les previews — un par palier
// qualitatif, avec métriques plausibles. Sur la canvas Xcode la
// génération LLM tombe en fallback textuel ; sur device, on voit
// la vraie phrase générée.

private let _faitsScore92 = FaitsJour(
    score: 92,
    tir: 88,
    tbrLevel1: 0.5,
    tbrLevel2: 0,
    tarLevel1: 11,
    tarLevel2: 0,
    hypoCount: 0,
    severeHypoCount: 0,
    peakTime: "13:30",
    peakValue: 178,
    mealContext: "déjeuner équilibré",
    sportContext: "marche 45 min"
)

private let _faitsScore78 = FaitsJour(
    score: 78,
    tir: 76,
    tbrLevel1: 1,
    tbrLevel2: 0,
    tarLevel1: 18,
    tarLevel2: 5,
    hypoCount: 1,
    severeHypoCount: 0,
    peakTime: "14:00",
    peakValue: 235,
    mealContext: nil,
    sportContext: nil
)

private let _faitsScore58 = FaitsJour(
    score: 58,
    tir: 60,
    tbrLevel1: 3,
    tbrLevel2: 0,
    tarLevel1: 28,
    tarLevel2: 9,
    hypoCount: 2,
    severeHypoCount: 0,
    peakTime: "20:00",
    peakValue: 268,
    mealContext: "dîner copieux",
    sportContext: nil
)

private let _faitsScore38 = FaitsJour(
    score: 38,
    tir: 45,
    tbrLevel1: 5,
    tbrLevel2: 1,
    tarLevel1: 32,
    tarLevel2: 12,
    hypoCount: 3,
    severeHypoCount: 0,
    peakTime: "16:00",
    peakValue: 298,
    mealContext: nil,
    sportContext: nil
)

private let _faitsScore22 = FaitsJour(
    score: 22,
    tir: 32,
    tbrLevel1: 8,
    tbrLevel2: 3,
    tarLevel1: 38,
    tarLevel2: 19,
    hypoCount: 5,
    severeHypoCount: 2,
    peakTime: "15:30",
    peakValue: 342,
    mealContext: "repas oublié + correction tardive",
    sportContext: nil
)

// Historique synthétique partagé par les previews — 6 valeurs pour
// J-6…J-2 (du plus ancien au plus récent), avec un creux dimanche et
// un pic mardi pour que la courbe ait du grain à voir. Le 7ᵉ point
// (jour affiché) est toujours `faits.score`, géré côté vue.
private let _historiquePreview: [Int?] = [65, 78, 55, 82, 90, 72]

#Preview("Score 92 — Très bonne") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(
                faits: _faitsScore92,
                date: Date(),
                historiquePrecedent: _historiquePreview
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}

#Preview("Score 78 — Bonne") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(
                faits: _faitsScore78,
                date: Date(),
                historiquePrecedent: _historiquePreview
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}

#Preview("Score 58 — Moyenne") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(
                faits: _faitsScore58,
                date: Date(),
                historiquePrecedent: _historiquePreview
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}

#Preview("Score 38 — Difficile") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(
                faits: _faitsScore38,
                date: Date(),
                historiquePrecedent: _historiquePreview
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}

#Preview("Score 22 — Très difficile") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(
                faits: _faitsScore22,
                date: Date(),
                historiquePrecedent: _historiquePreview
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}
