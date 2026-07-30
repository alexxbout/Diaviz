//
//  ContexteNormaliseGenerator.swift
//  diaviz
//

import FoundationModels

/// Résultat de catégorisation d'un texte de contexte de repas par Foundation
/// Models — soit un rattachement à une entrée déjà connue, soit une
/// proposition de nouvelle entrée. Un seul appel non-streamé (`respond`,
/// pas `streamResponse`) : job de fond sans consommateur incrémental,
/// contrairement à la narration du matin (`NarrationJourVue`).
@Generable
struct ContexteNormaliseResultat: Equatable, Sendable {
    @Guide(
        description: "Si ce texte correspond au MÊME événement qu'une entrée DÉJÀ listée ci-dessous, recopie EXACTEMENT (mot pour mot) son libellé existant. Sinon, laisse ce champ vide."
    )
    let libelleExistant: String?

    @Guide(
        description: "Libellé court (1 à 4 mots, en français, sans emoji, à la forme neutre) proposé pour ce nouvel événement — utilisé seulement si aucune correspondance existante."
    )
    let nouveauLibelle: String

    @Guide(description: "Un unique emoji représentatif de l'événement, existant ou nouveau.")
    let emoji: String
}

/// Construit la session Foundation Models et exécute la catégorisation.
/// L'availability est déjà vérifiée par l'appelant
/// (`ReferentielContextesService`) — ce type ne fait que l'appel + la
/// gestion d'erreur, pas le fallback.
enum ContexteNormaliseGenerator {

    /// Plafond d'entrées injectées dans le prompt — usage personnel, le
    /// référentiel ne devrait jamais s'approcher de cette taille, mais borne
    /// le prompt par sécurité si jamais il grossissait de façon inattendue.
    private static let maxEntreesDansPrompt = 100

    /// Règles persistantes : rôle, garde-fou non-médical, format attendu.
    /// Même séparation instructions/prompt que `PromptNarration` — le modèle
    /// on-device respecte mieux des règles posées comme système persistant
    /// que mêlées aux données du prompt.
    private static let instructions = """
    Tu catégorises de courts textes libres décrivant le CONTEXTE DE VIE \
    d'un repas (ex. « je prends la voiture », « stress au travail »), pour \
    un patient diabétique de type 1. Réponds en français.

    Ta tâche est UNIQUEMENT de rattacher ce texte à un événement déjà connu \
    (liste fournie) ou de proposer un nouveau libellé court. Tu ne dois \
    JAMAIS interpréter de donnée médicale ou de symptôme mentionné dans le \
    texte (ex. « hypo ressentie », « malaise », « fatigue ») — traite-le \
    uniquement comme une étiquette d'événement de vie, jamais comme une \
    donnée clinique à analyser ou commenter.

    Si le texte correspond au MÊME événement réel qu'une entrée déjà \
    listée (même en formulation différente, ex. "voiture" et "je prends la \
    voiture" sont le MÊME événement), recopie EXACTEMENT son libellé \
    existant dans `libelleExistant`. Sinon laisse `libelleExistant` vide et \
    propose un `nouveauLibelle` court (1 à 4 mots) et un `emoji` \
    représentatif.
    """

    static func generer(texte: String, referentiel: [ContexteNormalise]) async -> ContexteNormaliseResultat? {
        let liste = referentiel.prefix(maxEntreesDansPrompt)
            .map { "- \($0.emoji) \($0.libelle)" }
            .joined(separator: "\n")
        let prompt = """
        Événements déjà connus :
        \(liste.isEmpty ? "(aucun pour l'instant)" : liste)

        Nouveau texte à catégoriser : "\(texte)"
        """
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 60)

        do {
            let session = LanguageModelSession(instructions: instructions)
            let reponse = try await session.respond(
                to: prompt,
                generating: ContexteNormaliseResultat.self,
                options: options
            )
            return reponse.content
        } catch is CancellationError {
            return nil
        } catch {
            #if DEBUG
            print("[ContexteNormaliseGenerator] échec génération : \(error)")
            #endif
            return nil
        }
    }
}
