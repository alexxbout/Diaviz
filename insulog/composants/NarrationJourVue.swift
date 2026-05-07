//
//  NarrationJourVue.swift
//  insulog
//
//  Created by Alexandre on 06/05/2026.
//

import SwiftUI
import FoundationModels

// MARK: - Modèle d'entrée

/// Métriques agrégées d'une journée — entrée du composant de narration.
///
/// Toutes les unités sont en pourcentage sauf `score` (0–100), `hypoCount`,
/// `severeHypoCount` (entiers), et `peakValue` (mg/dL).
struct FaitsJour: Sendable, Equatable, Hashable {
    let score: Int
    let tir: Double
    let tbrLevel1: Double
    let tbrLevel2: Double
    let tarLevel1: Double
    let tarLevel2: Double
    let hypoCount: Int
    let severeHypoCount: Int
    let peakTime: String?
    let peakValue: Int?
    let mealContext: String?
    let sportContext: String?
}

// MARK: - Schéma de génération guidée

/// Phrase narrative découpée en segments typés sémantiquement.
///
/// Foundation Models impose un struct racine pour la génération guidée — on
/// enveloppe donc le tableau de segments dans `NarrationColoree`.
@Generable
struct NarrationColoree: Equatable, Sendable {
    @Guide(
        description: "Liste de segments composant la phrase narrative complète, dans l'ordre de lecture",
        .maximumCount(9)
    )
    let segments: [SegmentNarration]
}

/// Segment d'une phrase narrative coloré selon son type sémantique.
///
/// `kind` est volontairement une `String` contrainte par `@Guide(.anyOf)` plutôt
/// qu'un `enum` : la version PartiallyGenerated d'un enum n'est pas utilisable
/// pendant le streaming, alors qu'une string optionnelle l'est trivialement.
@Generable
struct SegmentNarration: Equatable, Sendable {
    @Guide(description: "Le texte de ce segment, tel qu'il doit s'afficher")
    let text: String

    @Guide(.anyOf(["neutral", "score", "tir", "hypos", "tar", "tbr", "peak"]))
    let kind: String
}

// MARK: - Mapping kind+valeurs → Couleur

/// Renvoie la couleur d'accent d'un segment selon son `kind` et la valeur
/// correspondante dans `faits`. Les seuils sont volontairement simples — à
/// calibrer après quelques jours d'usage réel.
private func couleur(pourType type: String, faits: FaitsJour) -> Color {
    switch type {
    case "score":
        return seuil(valeur: Double(faits.score), bonAuDessusDe: 70, mauvaisEnDessousDe: 50)
    case "tir":
        return seuil(valeur: faits.tir, bonAuDessusDe: 70, mauvaisEnDessousDe: 50)
    case "hypos":
        switch faits.hypoCount {
        case 0:     return .green
        case 1:     return .primary
        case 2...3: return .orange
        default:
            // Rouge plus foncé si au moins une hypo sévère, sinon rouge système.
            return faits.severeHypoCount > 0
                ? Color(red: 0.65, green: 0.05, blue: 0.10)
                : .red
        }
    case "tbr":
        let total = faits.tbrLevel1 + faits.tbrLevel2
        if total < 1 { return .primary }
        return total < 4 ? .orange : .red
    case "tar":
        let total = faits.tarLevel1 + faits.tarLevel2
        if total < 25 { return .primary }
        return total < 50 ? .orange : .red
    case "peak":
        guard let valeur = faits.peakValue else { return .primary }
        if valeur < 250 { return .primary }
        return valeur <= 300 ? .orange : .red
    default:
        return .primary
    }
}

private func seuil(valeur: Double, bonAuDessusDe: Double, mauvaisEnDessousDe: Double) -> Color {
    if valeur >= bonAuDessusDe { return .green }
    if valeur < mauvaisEnDessousDe { return .red }
    return .orange
}

// MARK: - Emoji d'humeur

/// Sélection d'emoji déterministe à partir du score. Mêmes paliers que
/// `CarteScoreQuotidien` (un seul emoji par palier ici, sans randomisation,
/// pour qu'un même score donne toujours le même emoji et reste prévisible
/// pendant le streaming). Si une hypo sévère est présente, on bascule sur
/// un emoji d'inquiétude indépendamment du score.
private func emojiHumeur(faits: FaitsJour) -> String {
    if faits.severeHypoCount > 0 { return "😟" }
    switch faits.score {
    case 90...:    return "🤩"
    case 75...89:  return "😊"
    case 60...74:  return "🙂"
    case 45...59:  return "😐"
    case 30...44:  return "😕"
    default:       return "😩"
    }
}

// MARK: - ViewModel

/// Pilote le cycle de génération de la phrase narrative et expose un `etat`
/// observable consommé par `NarrationJourVue`.
@MainActor
@Observable
final class NarrationViewModel {

    enum Etat: Equatable {
        case chargement
        case streaming(segments: [SegmentNarration])
        case termine(segments: [SegmentNarration])
        case fallback(texte: String)
    }

    private(set) var etat: Etat
    /// Si vrai, `demarrer(faits:)` ne fait rien. Utilisé par les previews pour
    /// figer un état visuel sans déclencher d'appel à Foundation Models.
    var figePreview: Bool

    init(etatInitial: Etat = .chargement, figePreview: Bool = false) {
        self.etat = etatInitial
        self.figePreview = figePreview
    }

    /// Déclenche le pipeline de génération. Appelé depuis `.task(id:)` qui
    /// gère l'annulation à la disparition de la vue (ou au changement de
    /// `faits`) — pas besoin de stocker la `Task` ici.
    func demarrer(faits: FaitsJour) async {
        guard !figePreview else { return }
        await executerGeneration(faits: faits)
    }

    // MARK: Pipeline de génération

    private func executerGeneration(faits: FaitsJour) async {
        etat = .chargement
        let modele = SystemLanguageModel.default
        guard modele.availability == .available else {
            etat = .fallback(texte: NarrationFallback.texte(pour: faits))
            return
        }

        // Sorti du `do` pour rester accessible dans le `catch` : si le stream
        // jette une erreur APRÈS avoir streamé du contenu (token limit,
        // guardrails, etc.), on garde ce qui a été généré plutôt que de
        // l'écraser par le fallback technique.
        var dernierAffiche: [SegmentNarration] = []

        do {
            // `instructions` = règles persistantes (rôle, longueur, format,
            // few-shot). Le modèle leur accorde plus de poids qu'à du texte
            // mid-prompt. Le `prompt` ne contient plus que les données du jour.
            let session = LanguageModelSession(instructions: PromptNarration.instructions)
            let prompt = PromptNarration.donneesPourPrompt(faits: faits)
            // 200 tokens ≈ 30 mots français + overhead JSON pour ~9 segments
            // avec marge confortable pour ne pas tronquer la fin.
            // temperature 0.4 limite les bavardages "coaching" du modèle.
            let options = GenerationOptions(
                temperature: 0.4,
                maximumResponseTokens: 200
            )
            let stream = session.streamResponse(
                to: prompt,
                generating: NarrationColoree.self,
                options: options
            )

            for try await snapshot in stream {
                if Task.isCancelled { return }
                // `snapshot.content` est un `NarrationColoree.PartiallyGenerated`
                // — mêmes champs que le type final, mais optionnels. On ne
                // « valide » un segment pour l'affichage qu'une fois ses deux
                // champs (text + kind) arrivés, sinon on afficherait du texte
                // sans couleur ou inversement.
                let partiel = snapshot.content
                let pretsAffichage = (partiel.segments ?? []).compactMap { brut -> SegmentNarration? in
                    guard let texte = brut.text, let type = brut.kind else { return nil }
                    return SegmentNarration(text: texte, kind: type)
                }

                if pretsAffichage != dernierAffiche {
                    dernierAffiche = pretsAffichage
                    etat = .streaming(segments: pretsAffichage)
                }

                // Garde-fou côté client : si le modèle continue à émettre des
                // segments au-delà du `.maximumCount` (rare mais possible), on
                // coupe explicitement le stream.
                if pretsAffichage.count >= 9 { break }
            }
        } catch is CancellationError {
            // Annulation propre (vue détruite, faits changés) : ne touche pas
            // à `etat`, le nouveau cycle s'en charge.
            return
        } catch {
            #if DEBUG
            print("[NarrationViewModel] échec génération : \(error)")
            #endif
            // Si l'erreur survient APRÈS qu'on a streamé du contenu, on
            // finalise avec ce qu'on a — l'utilisateur a déjà vu la phrase
            // arriver, l'écraser serait perçu comme un bug.
            if !dernierAffiche.isEmpty {
                etat = .termine(segments: dernierAffiche)
            } else {
                etat = .fallback(texte: NarrationFallback.texte(pour: faits))
            }
            return
        }

        // Stream terminé sans erreur.
        if dernierAffiche.isEmpty {
            etat = .fallback(texte: NarrationFallback.texte(pour: faits))
        } else {
            etat = .termine(segments: dernierAffiche)
        }
    }
}

// MARK: - Construction du prompt

/// Construit les `instructions` (règles persistantes envoyées à
/// `LanguageModelSession`) et le prompt par-tour (juste les données du jour).
///
/// Séparation volontaire : le modèle Apple on-device est petit et a tendance à
/// noyer les contraintes de format/longueur quand elles sont mêlées aux
/// données. Les `instructions` sont traitées comme un système prompt persistant
/// et beaucoup mieux respectées.
private enum PromptNarration {

    /// Règles persistantes : rôle, longueur, format, segmentation, few-shot.
    /// Volontairement courtes et concrètes — les listes longues dégradent la
    /// performance du modèle on-device.
    static let instructions: String = """
    Tu résumes la journée d'hier d'un patient diabétique de type 1 en \
    UNE SEULE PHRASE de 18 à 28 mots, terminée par UN SEUL POINT (le \
    dernier caractère). Réponds exclusivement en français.

    INTERDIT :
    - Plusieurs phrases ou plusieurs points dans la sortie. Si tu sens \
    le besoin de couper, utilise une virgule ou « avec ».
    - Tirets ou traits d'union (-, –, —).
    - L'expression « hyperglycémie de X % » : utilise plutôt \
    « X % du temps en hyper » ou « X % en hyper ».
    - L'expression « hypoglycémie de X % » : même règle, dis « X % en hypo ».

    Commence toujours par « Hier » ou « Hier soir ».

    PRIORISATION — mentionne 2 à 4 métriques au plus, dans cet ordre :
    1. Le score (toujours)
    2. Les hypoglycémies si > 0 (toujours important)
    3. Un pic glycémique > 250 mg/dL
    4. Le temps en hyper si > 25 %
    5. Le TIR si < 70 %
    Ignore systématiquement les métriques dans la zone normale.

    Découpe la phrase en segments JSON typés (champ `kind`) :
    - score : la mention du score (ex : "score 85")
    - tir : la mention du % en cible (ex : "78 % en cible")
    - hypos : la mention des hypoglycémies (ex : "4 hypoglycémies dont 1 sévère")
    - tar : la mention du temps en hyper (ex : "50 % en hyper")
    - peak : la mention d'un pic (ex : "pic à 312 mg/dL")
    - neutral : TOUT le reste — connecteurs (et, avec, malgré, dont, à), \
    ponctuation, espaces, formules d'introduction et de conclusion.

    Règles strictes :
    1. Un segment non-neutral contient UNIQUEMENT le chiffre et son libellé \
    minimal (3 ou 4 mots max), JAMAIS un mot de liaison.
    2. Les mots « et », « avec », « malgré », « dont », « à », « de », ainsi \
    que la ponctuation, sont TOUJOURS dans un segment neutral.
    3. Inclus les espaces de séparation dans le `text` des segments neutral.
    4. Maximum 9 segments au total.

    Exemple bonne journée (score=85, TIR=78 %, 0 hypo, hyper=11 %) :
    [{"text":"Hier, belle journée avec un ","kind":"neutral"},\
    {"text":"score 85","kind":"score"},{"text":" et ","kind":"neutral"},\
    {"text":"aucune hypoglycémie","kind":"hypos"},{"text":".","kind":"neutral"}]

    Exemple journée difficile (score=35, TIR=42 %, 4 hypos dont 1 sévère, \
    hyper=50 %, pic=312 mg/dL) — on garde les 3 plus marquantes :
    [{"text":"Hier, journée compliquée avec un ","kind":"neutral"},\
    {"text":"score 35","kind":"score"},{"text":", ","kind":"neutral"},\
    {"text":"4 hypoglycémies dont 1 sévère","kind":"hypos"},\
    {"text":" et ","kind":"neutral"},{"text":"50 % en hyper","kind":"tar"},\
    {"text":".","kind":"neutral"}]
    """

    /// Prompt par-tour : strictement les données + une consigne de ton brève.
    /// Les labels sont formulés de façon à être recopiables tels quels par le
    /// modèle (« Temps en hyper : 50 % » → « 50 % en hyper » dans la phrase).
    static func donneesPourPrompt(faits: FaitsJour) -> String {
        let totalTar = faits.tarLevel1 + faits.tarLevel2

        var lignes: [String] = [
            "Données de la journée d'hier :",
            "- Score : \(faits.score)/100",
            "- TIR : \(formatPourcent(faits.tir)) en cible",
        ]
        if faits.hypoCount > 0 {
            let severite = faits.severeHypoCount > 0 ? " dont \(faits.severeHypoCount) sévère(s)" : ""
            lignes.append("- \(faits.hypoCount) hypoglycémie(s)\(severite)")
        } else {
            lignes.append("- Aucune hypoglycémie")
        }
        if totalTar >= 25 {
            lignes.append("- Temps en hyper : \(formatPourcent(totalTar))")
        }
        if let heure = faits.peakTime, let valeur = faits.peakValue, valeur >= 250 {
            lignes.append("- Pic à \(heure) (\(valeur) mg/dL)")
        }
        lignes.append("")
        lignes.append(consigneTon(score: faits.score))
        lignes.append("Génère UNE SEULE phrase JSON, 18 à 28 mots, un seul point final. Commence par « Hier ».")
        return lignes.joined(separator: "\n")
    }

    private static func consigneTon(score: Int) -> String {
        switch score {
        case 86...:    return "Ton : félicitations brèves."
        case 70...85:  return "Ton : encourageant."
        case 50...69:  return "Ton : factuel."
        default:       return "Ton : empathique, sans jugement."
        }
    }

    private static func formatPourcent(_ valeur: Double) -> String {
        if valeur == floor(valeur) {
            return String(format: "%.0f%%", valeur)
        }
        return String(format: "%.1f%%", valeur)
    }
}

// MARK: - Fallback purement textuel

/// Phrase factuelle non générée — utilisée quand Apple Intelligence est
/// indisponible ou que la génération échoue. Ne jamais inventer de données.
private enum NarrationFallback {

    static func texte(pour faits: FaitsJour) -> String {
        let totalTar = faits.tarLevel1 + faits.tarLevel2
        var morceaux: [String] = ["Hier : score \(faits.score)/100"]
        morceaux.append("TIR \(formatPourcent(faits.tir))")
        morceaux.append("\(faits.hypoCount) hypo\(faits.hypoCount > 1 ? "s" : "")")
        if totalTar >= 5 {
            morceaux.append("hyper \(formatPourcent(totalTar))")
        }
        return morceaux.joined(separator: ", ") + "."
    }

    private static func formatPourcent(_ valeur: Double) -> String {
        if valeur == floor(valeur) {
            return String(format: "%.0f%%", valeur)
        }
        return String(format: "%.1f%%", valeur)
    }
}

// MARK: - Vue

/// Phrase narrative résumant une journée, générée par Foundation Models et
/// affichée en streaming avec coloration sémantique des mots-clés.
///
/// Le composant est conçu pour s'intégrer dans une carte parente : pas de
/// fond ni de bordure propres.
struct NarrationJourVue: View {

    let faits: FaitsJour

    @State private var modele: NarrationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(faits: FaitsJour) {
        self.faits = faits
        _modele = State(initialValue: NarrationViewModel())
    }

    /// Init de preview : permet d'injecter un état figé sans déclencher d'appel
    /// à Foundation Models (impossible dans la canvas Xcode).
    fileprivate init(faits: FaitsJour, modelePreview: NarrationViewModel) {
        self.faits = faits
        _modele = State(initialValue: modelePreview)
    }

    var body: some View {
        contenu
            .padding(16)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(libelleAccessibilite)
            .task(id: faits) {
                await modele.demarrer(faits: faits)
            }
    }

    @ViewBuilder
    private var contenu: some View {
        switch modele.etat {
        case .chargement:
            IndicateurChargement(reduceMotion: reduceMotion)

        case .streaming(let segments):
            phraseAttribuee(segments: segments, avecCurseur: true)

        case .termine(let segments):
            phraseAttribuee(segments: segments, avecCurseur: false)

        case .fallback(let texte):
            Text("\(emojiHumeur(faits: faits)) \(texte)")
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func phraseAttribuee(segments: [SegmentNarration], avecCurseur: Bool) -> some View {
        // Le curseur est concaténé inline au Text (pas en overlay) pour qu'il
        // suive la position réelle de fin du texte après wrap. TimelineView
        // re-évalue la closure 2 fois par seconde pour faire clignoter le
        // caractère « ▎ » via opacité.
        if avecCurseur {
            TimelineView(.periodic(from: .now, by: 0.5)) { contexte in
                phraseAvecCurseur(
                    segments: segments,
                    curseurVisible: reduceMotion
                        || Int(contexte.date.timeIntervalSince1970 * 2) % 2 == 0
                )
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            phraseRendu(segments: segments)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Concatène les segments dans un `Text` unique pour préserver le wrap.
    /// Insère un espace entre deux segments si ni la fin du précédent ni le
    /// début du suivant n'en contient un — filet de sécurité pour les cas où
    /// le LLM oublie l'espace de séparation malgré la consigne du prompt.
    /// Préfixé par un emoji d'humeur dérivé du score (déterministe).
    private func phraseRendu(segments: [SegmentNarration]) -> Text {
        var resultat = Text("\(emojiHumeur(faits: faits)) ")
        var precedent: SegmentNarration?
        for segment in segments {
            if besoinSeparateur(precedent: precedent, suivant: segment) {
                resultat = resultat + Text(" ")
            }
            let estNeutre = segment.kind == "neutral"
            resultat = resultat + Text(segment.text)
                .foregroundColor(couleur(pourType: segment.kind, faits: faits))
                .fontWeight(estNeutre ? .regular : .bold)
            precedent = segment
        }
        return resultat.font(.body)
    }

    private func besoinSeparateur(
        precedent: SegmentNarration?,
        suivant: SegmentNarration
    ) -> Bool {
        guard let precedent else { return false }
        guard let dernierCar = precedent.text.last,
              let premierCar = suivant.text.first else { return false }
        if dernierCar.isWhitespace || premierCar.isWhitespace { return false }
        // Pas d'espace inséré devant une ponctuation collée.
        if ",.;:!?)»".contains(premierCar) { return false }
        // Pas d'espace après une ouverture de parenthèse/guillemet.
        if "(«".contains(dernierCar) { return false }
        return true
    }

    private func phraseAvecCurseur(segments: [SegmentNarration], curseurVisible: Bool) -> Text {
        phraseRendu(segments: segments)
            + Text("▎")
                .font(.body)
                .foregroundColor(.primary.opacity(curseurVisible ? 1 : 0))
    }

    private var libelleAccessibilite: String {
        switch modele.etat {
        case .chargement:
            return "Résumé de la journée en cours de génération."
        case .streaming(let s), .termine(let s):
            return "Résumé de la journée : " + s.map(\.text).joined()
        case .fallback(let texte):
            return texte
        }
    }
}

// MARK: - Composants visuels internes

/// Trois points qui pulsent — chargement initial avant le premier segment.
private struct IndicateurChargement: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { contexte in
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(opacite(index: index, date: contexte.date))
                }
            }
            .frame(height: 20, alignment: .leading)
        }
    }

    private func opacite(index: Int, date: Date) -> Double {
        if reduceMotion { return 0.5 }
        let bucket = Int(date.timeIntervalSince1970 / 0.4) % 3
        return bucket == index ? 1.0 : 0.3
    }
}

// MARK: - Données d'aperçu

extension FaitsJour {
    static let apercuExcellent = FaitsJour(
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

    static let apercuDifficile = FaitsJour(
        score: 35,
        tir: 42,
        tbrLevel1: 6,
        tbrLevel2: 2,
        tarLevel1: 35,
        tarLevel2: 15,
        hypoCount: 4,
        severeHypoCount: 1,
        peakTime: "16:00",
        peakValue: 312,
        mealContext: "déjeuner copieux",
        sportContext: nil
    )

    static let apercuMoyen = FaitsJour(
        score: 68,
        tir: 64,
        tbrLevel1: 2,
        tbrLevel2: 0,
        tarLevel1: 28,
        tarLevel2: 6,
        hypoCount: 2,
        severeHypoCount: 0,
        peakTime: "20:00",
        peakValue: 268,
        mealContext: nil,
        sportContext: "course 30 min"
    )
}

// MARK: - Aperçus

#Preview("Score 92 — terminé") {
    NarrationJourVue(
        faits: .apercuExcellent,
        modelePreview: NarrationViewModel(
            etatInitial: .termine(segments: [
                SegmentNarration(text: "Belle journée : ", kind: "neutral"),
                SegmentNarration(text: "score 92", kind: "score"),
                SegmentNarration(text: " et ", kind: "neutral"),
                SegmentNarration(text: "TIR 88 %", kind: "tir"),
                SegmentNarration(text: ", sans la moindre hypoglycémie. ", kind: "neutral"),
                SegmentNarration(text: "Aucune hypo", kind: "hypos"),
                SegmentNarration(text: " et un pic léger à ", kind: "neutral"),
                SegmentNarration(text: "178 mg/dL après le déjeuner", kind: "peak"),
                SegmentNarration(text: " — bravo !", kind: "neutral"),
            ]),
            figePreview: true
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Score 35 — terminé") {
    NarrationJourVue(
        faits: .apercuDifficile,
        modelePreview: NarrationViewModel(
            etatInitial: .termine(segments: [
                SegmentNarration(text: "Journée compliquée : ", kind: "neutral"),
                SegmentNarration(text: "score 35", kind: "score"),
                SegmentNarration(text: ", ", kind: "neutral"),
                SegmentNarration(text: "4 hypoglycémies dont 1 sévère", kind: "hypos"),
                SegmentNarration(text: " et ", kind: "neutral"),
                SegmentNarration(text: "50 % en hyper", kind: "tar"),
                SegmentNarration(text: " avec un pic à ", kind: "neutral"),
                SegmentNarration(text: "312 mg/dL", kind: "peak"),
                SegmentNarration(text: ". Demain est une nouvelle page.", kind: "neutral"),
            ]),
            figePreview: true
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Score 68 — streaming en cours") {
    NarrationJourVue(
        faits: .apercuMoyen,
        modelePreview: NarrationViewModel(
            etatInitial: .streaming(segments: [
                SegmentNarration(text: "Journée correcte : ", kind: "neutral"),
                SegmentNarration(text: "score 68", kind: "score"),
                SegmentNarration(text: " avec ", kind: "neutral"),
                SegmentNarration(text: "TIR 64 %", kind: "tir"),
                SegmentNarration(text: ", la course a ", kind: "neutral"),
            ]),
            figePreview: true
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Chargement initial") {
    NarrationJourVue(
        faits: .apercuExcellent,
        modelePreview: NarrationViewModel(
            etatInitial: .chargement,
            figePreview: true
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Fallback — IA indisponible") {
    NarrationJourVue(
        faits: .apercuExcellent,
        modelePreview: NarrationViewModel(
            etatInitial: .fallback(
                texte: "Hier : score 92/100, TIR 88 %, 0 hypo."
            ),
            figePreview: true
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

// MARK: - Preview interactive

/// Wrapper de preview qui appelle réellement Foundation Models (sur device
/// uniquement — la canvas Xcode bascule en fallback). Le bouton « Régénérer »
/// recrée la vue via `.id(compteur)` pour repartir d'un VM vierge à chaque
/// clic, ce qui force `task(id:)` à relancer la génération.
private struct PreviewBoutonGenerer: View {
    let faits: FaitsJour
    @State private var compteur = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NarrationJourVue(faits: faits)
                .id(compteur)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

            Button {
                compteur += 1
            } label: {
                Label(compteur == 0 ? "Générer" : "Régénérer", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Live — données excellentes") {
    PreviewBoutonGenerer(faits: .apercuExcellent)
}

#Preview("Live — données difficiles") {
    PreviewBoutonGenerer(faits: .apercuDifficile)
}
