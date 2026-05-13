//
//  NarrationJourVue.swift
//  diaviz
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
        description: "Liste de segments composant la narration complète, dans l'ordre de lecture",
        .maximumCount(20)
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

/// Sets d'emojis par humeur. Un emoji est tiré aléatoirement à la création
/// de la vue (puis stocké en `@State`), et reste stable jusqu'au prochain
/// changement de `faits` (ou clic « Régénérer » en preview).
///
/// Une hypo sévère force le set `hypoSevere` indépendamment du score :
/// un score « bon » avec une hypo sévère ne doit pas afficher 😎.
private enum EmojisHumeur {
    // 90+ : grosse fête.
    static let excellent  = [
        "🤩", "🥳", "🎉", "🎊", "🍾", "🥂", "🚀", "⭐️", "🌟", "💫",
        "✨", "🔥", "💯", "🏆", "🥇", "👏", "🙌", "💪", "🤘", "🤩",
        "🌈", "⚡️", "🎯", "🥹", "😎", "😄", "🌠", "🎆"
    ]
    // 75–89 : positif sans en faire trop.
    static let bon = [
        "😊", "🙂", "😌", "😄", "☺️", "👍", "🙌", "✨", "💚", "⭐️",
        "🌟", "👌", "💪", "🌤", "🍀", "👏", "🤝"
    ]
    // 60–74 : neutre légèrement positif.
    static let correct = [
        "🙂", "😌", "😏", "🙃", "🫡", "👌", "🤞", "😉", "☺️", "✌️"
    ]
    // 45–59 : pensif.
    static let moyen = [
        "😐", "😶", "🤔", "😶‍🌫️", "🫥", "🤷", "😬", "😏", "🥱", "😪"
    ]
    // 30–44 : léger inconfort.
    static let faible = [
        "😕", "😟", "🫤", "😬", "😣", "😶‍🌫️", "😮‍💨", "😔", "🫨", "😵‍💫"
    ]
    // 0–29 : découragé.
    static let mauvais = [
        "😩", "😣", "😖", "😞", "😔", "😪", "😓", "🥲", "😢", "🥺", "🫠"
    ]
    // Hypo sévère — alerte sans dramatiser.
    static let hypoSevere = [
        "😟", "😬", "🫤", "😣", "🤕", "😨", "😖", "🤒", "😵", "🥴"
    ]

    static func tirage(faits: FaitsJour) -> String {
        candidats(faits: faits).randomElement() ?? "🙂"
    }

    private static func candidats(faits: FaitsJour) -> [String] {
        if faits.severeHypoCount > 0 { return hypoSevere }
        switch faits.score {
        case 90...:    return excellent
        case 75...89:  return bon
        case 60...74:  return correct
        case 45...59:  return moyen
        case 30...44:  return faible
        default:       return mauvais
        }
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
        /// Génération en cours — segments partiels reçus jusqu'ici.
        /// Consommé par `SheetScoreMatin` pour afficher le texte qui
        /// "pousse" au fur et à mesure ; ignoré (= loader) par
        /// `NarrationJourVue` qui n'affiche que le résultat final.
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
        // jette une erreur APRÈS avoir consommé du contenu (token limit,
        // guardrails, etc.), on finalise avec ce qui a été reçu plutôt que
        // de tomber sur le fallback technique.
        var dernierRecu: [SegmentNarration] = []

        do {
            // `instructions` = règles persistantes (rôle, longueur, format,
            // few-shot). Le modèle leur accorde plus de poids qu'à du texte
            // mid-prompt. Le `prompt` ne contient plus que les données du jour.
            let session = LanguageModelSession(instructions: PromptNarration.instructions)
            let prompt = PromptNarration.donneesPourPrompt(faits: faits)
            let options = GenerationOptions(
                temperature: 0.35,
                maximumResponseTokens: 250
            )
            let stream = session.streamResponse(
                to: prompt,
                generating: NarrationColoree.self,
                options: options
            )

            // On consomme le stream et publie l'état `.streaming` à chaque
            // snapshot non-vide → les consommateurs intéressés (la sheet
            // « Score du matin ») peuvent afficher le texte qui pousse en
            // direct ; `NarrationJourVue` ignore `.streaming` et garde le
            // loader jusqu'au `.termine` final.
            for try await snapshot in stream {
                if Task.isCancelled { return }
                let partiel = snapshot.content
                let pretsAffichage = (partiel.segments ?? []).compactMap { brut -> SegmentNarration? in
                    guard let texte = brut.text, let type = brut.kind else { return nil }
                    return SegmentNarration(text: texte, kind: type)
                }
                if pretsAffichage != dernierRecu {
                    dernierRecu = pretsAffichage
                    if !pretsAffichage.isEmpty {
                        etat = .streaming(segments: pretsAffichage)
                    }
                }
                // Garde-fou côté client : si le modèle continue à émettre des
                // segments au-delà du `.maximumCount` (rare mais possible), on
                // coupe explicitement le stream.
                if dernierRecu.count >= 20 { break }
            }
        } catch is CancellationError {
            // Annulation propre (vue détruite, faits changés) : ne touche pas
            // à `etat`, le nouveau cycle s'en charge.
            return
        } catch {
            #if DEBUG
            print("[NarrationViewModel] échec génération : \(error)")
            #endif
            if !dernierRecu.isEmpty {
                etat = .termine(segments: dernierRecu)
            } else {
                etat = .fallback(texte: NarrationFallback.texte(pour: faits))
            }
            return
        }

        if dernierRecu.isEmpty {
            etat = .fallback(texte: NarrationFallback.texte(pour: faits))
        } else {
            etat = .termine(segments: dernierRecu)
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
    Tu rédiges un résumé chaleureux et personnel de la journée d'hier \
    pour un patient diabétique de type 1 qui lit cette phrase tous les \
    matins. Réponds en français.

    LONGUEUR : EXACTEMENT 3 phrases. 60 à 90 mots au total. Termine par \
    un point final. Si tu dépasses 90 mots, tu as échoué : sois concis.

    ADRESSE : impersonnelle ou tutoiement. JAMAIS « le patient », \
    JAMAIS « il/elle », JAMAIS de formulation médicale en 3ᵉ personne.

    TON : narratif et personnel plutôt que strictement clinique. Tu \
    peux décrire un moment, situer un événement (« autour de midi », \
    « après le déjeuner », « dans l'après-midi »), évoquer une \
    sensation possible (« une journée plus stable », « un coup de \
    fatigue probable »). Bienveillant sans patronage. Tu PEUX et \
    DOIS ajouter une vraie note humaine — encourageante les bons \
    jours, rassurante les mauvais — pas juste un constat factuel.

    INTERDIT (le texte est à refuser s'il contient une de ces \
    formules creuses) :
    - « la vigilance continue est recommandée »
    - « les résultats sont encourageants »
    - « un suivi régulier est essentiel »
    - « bien gérer son diabète », « gérer son diabète »
    - « les ajustements alimentaires et les injections »
    - « le patient » / « la patiente »
    - « bravo », « formidable », « excellent », « belle »
    - exclamations (!), emojis, tirets (-, –, —)
    - répéter la même information dans deux phrases différentes
    - « hyperglycémie de X % » → dis « X % en hyper »
    - « hypoglycémie de X % » → dis « X % en hypo »

    Commence toujours par « Hier » ou « Hier soir ».

    STRUCTURE OBLIGATOIRE (3 phrases, chacune apporte une info NOUVELLE) :
    - Phrase 1 (~25 mots) : ouverture avec le score et les métriques \
    marquantes, sur un ton qui campe l'ambiance de la journée.
    - Phrase 2 (~25 mots) : détail concret et situé d'un événement \
    précis — un pic à telle heure, une hypo dans tel contexte, une \
    période instable. Sois descriptif, pas juste statistique.
    - Phrase 3 (~20 mots) : mise en perspective humaine — note \
    rassurante, encouragement discret, ou observation qui invite à \
    une légère piste d'amélioration. Cette phrase apporte la chaleur.

    PRIORISATION des métriques (dans cet ordre, ignore les zones \
    normales) :
    1. Le score (toujours)
    2. Les hypoglycémies si > 0
    3. Un pic glycémique > 250 mg/dL
    4. Le temps en hyper si > 25 %
    5. Le TIR si < 70 %

    Découpe le texte en segments JSON typés (champ `kind`) :
    - score : la mention du score (ex : "score 85")
    - tir : la mention du % en cible (ex : "78 % en cible")
    - hypos : la mention des hypoglycémies (ex : "4 hypoglycémies dont 1 sévère")
    - tar : la mention du temps en hyper (ex : "50 % en hyper")
    - peak : la mention d'un pic (ex : "pic à 312 mg/dL")
    - neutral : TOUT le reste — connecteurs (et, avec, malgré, dont, à), \
    ponctuation, espaces, formules d'introduction et de conclusion, \
    phrases d'observation complémentaires.

    Règles strictes :
    1. Un segment non-neutral contient UNIQUEMENT le chiffre et son libellé \
    minimal (3 ou 4 mots max), JAMAIS un mot de liaison.
    2. Les mots « et », « avec », « malgré », « dont », « à », « de », ainsi \
    que la ponctuation, sont TOUJOURS dans un segment neutral.
    3. Inclus les espaces de séparation dans le `text` des segments neutral.
    4. Maximum 20 segments au total.

    Exemple bonne journée (score=85, TIR=78 %, 0 hypo, hyper=11 %) :
    [{"text":"Hier, journée plutôt stable avec un ","kind":"neutral"},\
    {"text":"score 85","kind":"score"},{"text":" et ","kind":"neutral"},\
    {"text":"aucune hypoglycémie","kind":"hypos"},\
    {"text":" sur l'ensemble de la journée. ","kind":"neutral"},\
    {"text":"Les glycémies sont restées dans la cible la majorité du temps, avec juste un léger passage en hyper en début d'après-midi. ","kind":"neutral"},\
    {"text":"Une journée comme celle-ci montre que le rythme actuel te convient bien, continue sur cette lancée.","kind":"neutral"}]

    Exemple journée difficile (score=35, TIR=42 %, 4 hypos dont 1 sévère, \
    hyper=50 %, pic=312 mg/dL) :
    [{"text":"Hier soir, journée plus compliquée avec un ","kind":"neutral"},\
    {"text":"score 35","kind":"score"},{"text":", ","kind":"neutral"},\
    {"text":"4 hypoglycémies dont 1 sévère","kind":"hypos"},\
    {"text":" et ","kind":"neutral"},{"text":"50 % en hyper","kind":"tar"},\
    {"text":". Le pic à ","kind":"neutral"},\
    {"text":"312 mg/dL","kind":"peak"},\
    {"text":" est survenu autour du déjeuner, peut-être un repas plus chargé en glucides que prévu. ","kind":"neutral"},\
    {"text":"Pas d'inquiétude, ces journées arrivent — un coup d'œil au ratio du midi pourrait suffire à éviter la prochaine fois.","kind":"neutral"}]
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
        lignes.append("Génère EXACTEMENT 3 phrases (60 à 90 mots), terminé par un point final. Commence par « Hier ». Pas de formules creuses, jamais « le patient ».")
        return lignes.joined(separator: "\n")
    }

    private static func consigneTon(score: Int) -> String {
        // Volontairement sobre quel que soit le score : pas de superlatif
        // sur les bons jours (« bravo », « excellent »), pas de patronage
        // sur les mauvais (« courage », « tu vas y arriver »). Juste les
        // chiffres avec un mot d'ouverture neutre.
        switch score {
        case 86...:    return "Ton : neutre. Énonce les chiffres sans aucun superlatif."
        case 70...85:  return "Ton : neutre, observationnel."
        case 50...69:  return "Ton : factuel."
        default:       return "Ton : factuel, sobre. Pas de patronage ni de message d'espoir."
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
/// affichée d'un bloc avec coloration sémantique des mots-clés.
///
/// Pas de fond ni de bordure : le composant s'affiche en pleine largeur,
/// son padding interne suffit à l'écarter des bords de l'écran.
struct NarrationJourVue: View {

    let faits: FaitsJour

    @State private var modele: NarrationViewModel
    @State private var emoji: String

    init(faits: FaitsJour) {
        self.faits = faits
        _modele = State(initialValue: NarrationViewModel())
        _emoji = State(initialValue: EmojisHumeur.tirage(faits: faits))
    }

    /// Init de preview : permet d'injecter un VM figé sur un état précis sans
    /// déclencher d'appel à Foundation Models.
    fileprivate init(
        faits: FaitsJour,
        modelePreview: NarrationViewModel
    ) {
        self.faits = faits
        _modele = State(initialValue: modelePreview)
        _emoji = State(initialValue: EmojisHumeur.tirage(faits: faits))
    }

    var body: some View {
        contenu
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(libelleAccessibilite)
            .task(id: faits) {
                emoji = EmojisHumeur.tirage(faits: faits)
                await modele.demarrer(faits: faits)
            }
    }

    @ViewBuilder
    private var contenu: some View {
        switch modele.etat {
        case .chargement, .streaming:
            // `.streaming` ignoré ici : on ne montre le texte qu'une
            // fois la génération terminée pour rester sobre dans ce
            // contexte (carte). La sheet « Score du matin » utilise
            // un rendu différent qui consomme `.streaming`.
            IndicateurChargement()

        case .termine(let segments):
            Text(phraseRendu(segments: segments))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

        case .fallback(let texte):
            Text("\(nettoyerFin(texte)) \(emoji)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Concatène les segments dans un `AttributedString` unique pour préserver
    /// le wrap. Insère un espace entre deux segments si ni la fin du précédent
    /// ni le début du suivant n'en contient un — filet de sécurité pour les
    /// cas où le LLM oublie l'espace de séparation malgré la consigne du prompt.
    ///
    /// Retire le point final du dernier segment et append l'emoji à la fin
    /// de la phrase.
    private func phraseRendu(segments: [SegmentNarration]) -> AttributedString {
        let segmentsTraites = segmentsSansPointFinal(segments)

        var resultat = AttributedString("")

        var precedent: SegmentNarration?
        for segment in segmentsTraites {
            if besoinSeparateur(precedent: precedent, suivant: segment) {
                var sep = AttributedString(" ")
                sep.font = .title2.weight(.bold)
                resultat.append(sep)
            }
            let estNeutre = segment.kind == "neutral"
            var segAttr = AttributedString(segment.text)
            segAttr.foregroundColor = couleur(pourType: segment.kind, faits: faits)
            segAttr.font = .title2.weight(estNeutre ? .bold : .heavy)
            resultat.append(segAttr)
            precedent = segment
        }

        var emojiAttr = AttributedString(" \(emoji)")
        emojiAttr.font = .title2
        resultat.append(emojiAttr)
        return resultat
    }

    /// Retire en cascade les `.` et espaces de fin sur les derniers segments —
    /// supprime aussi un dernier segment qui ne contiendrait QUE le point.
    private func segmentsSansPointFinal(_ segments: [SegmentNarration]) -> [SegmentNarration] {
        var resultat = segments
        while let dernier = resultat.last {
            let nettoye = nettoyerFin(dernier.text)
            if nettoye.isEmpty {
                resultat.removeLast()
                continue
            }
            if nettoye != dernier.text {
                resultat[resultat.count - 1] = SegmentNarration(
                    text: nettoye, kind: dernier.kind
                )
            }
            break
        }
        return resultat
    }

    /// Strip itératif des `.` et caractères blancs de fin de chaîne.
    private func nettoyerFin(_ texte: String) -> String {
        var resultat = texte
        while let dernier = resultat.last, dernier == "." || dernier.isWhitespace {
            resultat.removeLast()
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
        // Pas d'espace inséré devant une ponctuation collée.
        if ",.;:!?)»".contains(premierCar) { return false }
        // Pas d'espace après une ouverture de parenthèse/guillemet.
        if "(«".contains(dernierCar) { return false }
        return true
    }

    private var libelleAccessibilite: String {
        switch modele.etat {
        case .chargement, .streaming:
            return "Résumé de la journée en cours de génération."
        case .termine(let s):
            return "Résumé de la journée : " + s.map(\.text).joined()
        case .fallback(let texte):
            return texte
        }
    }
}

// MARK: - Composants visuels internes

/// Trois points qui pulsent — chargement pendant la génération.
private struct IndicateurChargement: View {
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
            .frame(height: 24, alignment: .leading)
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
                .frame(height: 24, alignment: .leading)
            }
        }
    }

    private func opacite(index: Int, date: Date) -> Double {
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

// MARK: - Aperçus figés

#Preview("Score 92 — terminé") {
    VStack {
        Spacer()
        NarrationJourVue(
            faits: .apercuExcellent,
            modelePreview: NarrationViewModel(
                etatInitial: .termine(segments: [
                    SegmentNarration(text: "Hier, journée correcte avec un ", kind: "neutral"),
                    SegmentNarration(text: "score 92", kind: "score"),
                    SegmentNarration(text: " et ", kind: "neutral"),
                    SegmentNarration(text: "TIR 88 %", kind: "tir"),
                    SegmentNarration(text: ", ", kind: "neutral"),
                    SegmentNarration(text: "aucune hypoglycémie", kind: "hypos"),
                    SegmentNarration(text: ".", kind: "neutral"),
                ]),
                figePreview: true
            )
        )
        Spacer()
    }
}

#Preview("Score 35 — terminé") {
    VStack {
        Spacer()
        NarrationJourVue(
            faits: .apercuDifficile,
            modelePreview: NarrationViewModel(
                etatInitial: .termine(segments: [
                    SegmentNarration(text: "Hier, ", kind: "neutral"),
                    SegmentNarration(text: "score 35", kind: "score"),
                    SegmentNarration(text: ", ", kind: "neutral"),
                    SegmentNarration(text: "4 hypoglycémies dont 1 sévère", kind: "hypos"),
                    SegmentNarration(text: " et ", kind: "neutral"),
                    SegmentNarration(text: "50 % en hyper", kind: "tar"),
                    SegmentNarration(text: " avec un pic à ", kind: "neutral"),
                    SegmentNarration(text: "312 mg/dL", kind: "peak"),
                    SegmentNarration(text: ".", kind: "neutral"),
                ]),
                figePreview: true
            )
        )
        Spacer()
    }
}

#Preview("Chargement") {
    VStack {
        Spacer()
        NarrationJourVue(
            faits: .apercuExcellent,
            modelePreview: NarrationViewModel(
                etatInitial: .chargement,
                figePreview: true
            )
        )
        Spacer()
    }
}

#Preview("Fallback — IA indisponible") {
    VStack {
        Spacer()
        NarrationJourVue(
            faits: .apercuExcellent,
            modelePreview: NarrationViewModel(
                etatInitial: .fallback(
                    texte: "Hier : score 92/100, TIR 88 %, 0 hypo."
                ),
                figePreview: true
            )
        )
        Spacer()
    }
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
        VStack(spacing: 16) {
            Spacer()
            NarrationJourVue(faits: faits)
                .id(compteur)
            Spacer()
            Button {
                compteur += 1
            } label: {
                Label(compteur == 0 ? "Générer" : "Régénérer", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}

#Preview("Live — données excellentes") {
    PreviewBoutonGenerer(faits: .apercuExcellent)
}

#Preview("Live — données difficiles") {
    PreviewBoutonGenerer(faits: .apercuDifficile)
}
