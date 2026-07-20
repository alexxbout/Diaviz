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
