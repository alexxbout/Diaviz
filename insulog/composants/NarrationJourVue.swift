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

/// Sets d'emojis par humeur. Plusieurs candidats par palier — la View
/// tire aléatoirement à la création (puis stocke en `@State`), pour que
/// le composant garde le MÊME emoji pendant tout le streaming et que
/// chaque clic « Régénérer » donne potentiellement un emoji différent.
///
/// Une hypo sévère force le set `hypoSevere` indépendamment du score :
/// un score « bon » avec une hypo sévère ne doit pas afficher 😎.
private enum EmojisHumeur {
    static let hypoSevere = ["😟", "😬", "🫤", "😣"]
    static let excellent  = ["🤩", "😄", "😎", "🥳"]            // 90+
    static let bon        = ["😊", "🙂", "😌", "😄"]            // 75–89
    static let correct    = ["🙂", "😌", "😏", "🙃"]            // 60–74
    static let moyen      = ["😐", "😶", "🤔", "😶‍🌫️"]         // 45–59
    static let faible     = ["😕", "😟", "🫤", "😬"]            // 30–44
    static let mauvais    = ["😩", "😣", "😖", "😞"]            // 0–29

    static func tirage(faits: FaitsJour) -> String {
        let candidats: [String]
        if faits.severeHypoCount > 0 {
            candidats = hypoSevere
        } else {
            switch faits.score {
            case 90...:    candidats = excellent
            case 75...89:  candidats = bon
            case 60...74:  candidats = correct
            case 45...59:  candidats = moyen
            case 30...44:  candidats = faible
            default:       candidats = mauvais
            }
        }
        return candidats.randomElement() ?? "🙂"
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
    /// Conservé pour API symétrique mais n'est plus utilisé dans le VM :
    /// l'animation de hauteur du conteneur est maintenant pilotée côté View
    /// via un `@Binding<Bool>` exposé au parent.
    var animerTransitions: Bool = true

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

    Le ton est sobre et factuel. Le patient lit cette phrase tous les \
    matins : pas de félicitations excessives, pas d'exclamations, pas \
    de coaching, pas de mots comme « bravo », « excellent », « belle », \
    « formidable ». Énonce les faits avec mesure.

    N'utilise PAS d'emoji dans la phrase. Le code en ajoutera un \
    automatiquement à la fin de l'affichage.

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
    [{"text":"Hier, journée correcte avec un ","kind":"neutral"},\
    {"text":"score 85","kind":"score"},{"text":" et ","kind":"neutral"},\
    {"text":"aucune hypoglycémie","kind":"hypos"},{"text":".","kind":"neutral"}]

    Exemple journée difficile (score=35, TIR=42 %, 4 hypos dont 1 sévère, \
    hyper=50 %, pic=312 mg/dL) — on garde les 3 plus marquantes :
    [{"text":"Hier, ","kind":"neutral"},\
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
/// affichée en streaming avec coloration sémantique des mots-clés.
///
/// Le composant est conçu pour s'intégrer dans une carte parente : pas de
/// fond ni de bordure propres.
struct NarrationJourVue: View {

    let faits: FaitsJour

    /// Binding exposé au parent pour qu'il puisse animer ses propres modifiers
    /// (background de carte, glow effect…) à la transition « dots → texte ».
    /// `withAnimation` à l'intérieur du VM ne propage pas toujours sa
    /// transaction aux modifiers du parent ; passer par un binding observable
    /// au niveau parent permet d'y appliquer un `.animation(_, value: ...)`
    /// qui couvre toute sa chaîne.
    @Binding private var contenuVisible: Bool

    @State private var modele: NarrationViewModel
    @State private var emojiChoisi: String
    @State private var typewriterStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(faits: FaitsJour, contenuVisible: Binding<Bool> = .constant(false)) {
        self.faits = faits
        _contenuVisible = contenuVisible
        _modele = State(initialValue: NarrationViewModel())
        _emojiChoisi = State(initialValue: EmojisHumeur.tirage(faits: faits))
        _typewriterStart = State(initialValue: nil)
    }

    /// Init de preview : pour une preview figée en `.termine`, on laisse
    /// `typewriterStart` à `nil` → le rendu affiche tout immédiatement.
    fileprivate init(
        faits: FaitsJour,
        modelePreview: NarrationViewModel,
        contenuVisible: Binding<Bool> = .constant(false)
    ) {
        self.faits = faits
        _contenuVisible = contenuVisible
        _modele = State(initialValue: modelePreview)
        _emojiChoisi = State(initialValue: EmojisHumeur.tirage(faits: faits))
        _typewriterStart = State(initialValue: nil)
    }

    private var afficheTexte: Bool {
        switch modele.etat {
        case .termine, .fallback: return true
        case .chargement, .streaming: return false
        }
    }

    /// Vitesse du typewriter en caractères par seconde.
    private static let vitesseTypewriter: Double = 24

    /// Durée du fade-in de chaque lettre, exprimée en multiples de
    /// « char-time » (1 / vitesseTypewriter). 2 ≈ 83 ms à 24 cps.
    /// Plusieurs lettres sont donc partiellement visibles à un instant
    /// donné, ce qui donne une cascade visible.
    private static let largeurFondu: Double = 2

    var body: some View {
        contenu
            .padding(16)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(libelleAccessibilite)
            .task(id: faits) {
                emojiChoisi = EmojisHumeur.tirage(faits: faits)
                typewriterStart = nil
                modele.animerTransitions = !reduceMotion
                contenuVisible = afficheTexte
                await modele.demarrer(faits: faits)
            }
            .onChange(of: afficheTexte) { _, nouveau in
                contenuVisible = nouveau
            }
            // Démarre le typewriter à la transition `.streaming` → `.termine`.
            // En reduceMotion on laisse `typewriterStart = nil` → tout
            // s'affiche d'un coup sans animation.
            .onChange(of: modele.etat) { _, nouveau in
                if case .termine = nouveau, !reduceMotion {
                    typewriterStart = .now
                }
            }
    }

    @ViewBuilder
    private var contenu: some View {
        switch modele.etat {
        case .chargement, .streaming:
            IndicateurChargement(reduceMotion: reduceMotion)

        case .termine(let segments):
            if let start = typewriterStart {
                // TimelineView(.animation) garantit une re-évaluation au
                // refresh rate (60–120 Hz) — ce qui permet à `progressChars`
                // d'évoluer en continu et à `phraseRenduTypewriter` de
                // recalculer l'opacité de chaque caractère à chaque frame.
                TimelineView(.animation) { contexte in
                    let elapsed = contexte.date.timeIntervalSince(start)
                    let progressChars = elapsed * Self.vitesseTypewriter
                    let total = segments.reduce(0) { $0 + $1.text.count }
                    let fini = progressChars >= Double(total)

                    Text(phraseRenduTypewriter(
                        segments: segments,
                        progressChars: progressChars,
                        finalise: fini
                    ))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // typewriterStart == nil → reduceMotion ou preview figée :
                // on affiche tout d'un coup, sans animation.
                Text(phraseRendu(segments: segments, finalise: true))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .fallback(let texte):
            Text("\(nettoyerFin(texte)) \(emojiChoisi)")
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    /// Construit l'`AttributedString` pendant le typewriter : chaque caractère
    /// reçoit une opacité dérivée de `progressChars - position` (clamp 0…1),
    /// étalée sur `largeurFondu` char-times → plusieurs lettres partielles
    /// simultanément, cascade visible. Un `baselineOffset` négatif additionnel
    /// fait remonter chaque lettre depuis ~4 pt en dessous de sa position
    /// finale au fur et à mesure de son apparition (slide-in).
    private func phraseRenduTypewriter(
        segments: [SegmentNarration],
        progressChars: Double,
        finalise: Bool
    ) -> AttributedString {
        let segmentsTraites = finalise ? segmentsSansPointFinal(segments) : segments

        var resultat = AttributedString("")
        resultat.font = .body

        // On n'append un caractère qu'une fois son fade démarré (progresLocal > 0).
        // Conséquence : l'AttributedString grandit avec le typewriter, donc la
        // hauteur du Text et celle de la carte parente grandissent en lockstep.
        // Le saccadement précédent venait du baselineOffset (qui faisait varier
        // l'ascent/descent à chaque frame) — sans lui, l'opacité pure suffit à
        // faire apparaître les lettres en douceur.
        var position = 0
        var precedent: SegmentNarration?
        for segment in segmentsTraites {
            if besoinSeparateur(precedent: precedent, suivant: segment) {
                let progresLocal = clamp01(
                    (progressChars - Double(position)) / Self.largeurFondu
                )
                if progresLocal > 0 {
                    var sep = AttributedString(" ")
                    sep.font = .body
                    sep.foregroundColor = Color.primary.opacity(progresLocal)
                    resultat.append(sep)
                }
                position += 1
            }
            let estNeutre = segment.kind == "neutral"
            let baseColor = couleur(pourType: segment.kind, faits: faits)
            let weight: Font.Weight = estNeutre ? .regular : .bold
            for char in segment.text {
                let progresLocal = clamp01(
                    (progressChars - Double(position)) / Self.largeurFondu
                )
                if progresLocal > 0 {
                    var charAttr = AttributedString(String(char))
                    charAttr.font = .body.weight(weight)
                    charAttr.foregroundColor = baseColor.opacity(progresLocal)
                    resultat.append(charAttr)
                }
                position += 1
            }
            precedent = segment
        }

        if finalise {
            var emojiAttr = AttributedString(" \(emojiChoisi)")
            emojiAttr.font = .body
            resultat.append(emojiAttr)
        }

        return resultat
    }

    private func clamp01(_ x: Double) -> Double {
        max(0, min(1, x))
    }

    /// Concatène les segments dans un `Text` unique pour préserver le wrap.
    /// Insère un espace entre deux segments si ni la fin du précédent ni le
    /// début du suivant n'en contient un — filet de sécurité pour les cas où
    /// le LLM oublie l'espace de séparation malgré la consigne du prompt.
    ///
    /// Emoji : le LLM doit placer le marqueur `{emoji}` à un endroit naturel.
    /// - Si le placeholder est présent : on le substitue par l'emoji déterministe.
    /// - Si absent ET stream pas encore terminé : on n'affiche AUCUN emoji
    ///   (évite que l'emoji apparaisse au début pendant le streaming puis
    ///   « saute » à sa position finale quand le LLM l'émet plus tard).
    /// - Si absent ET stream terminé : fallback préfixe.
    /// Construit l'`AttributedString` complète (sans curseur) à partir des
    /// segments. Migration iOS 26 : `Text + Text` est déprécié au profit
    /// d'AttributedString ou de l'interpolation, on choisit AttributedString
    /// car c'est plus naturel pour empiler des segments à attributs variables.
    ///
    /// Quand `finalise == true` (état `.termine`), on retire le point final
    /// du dernier segment et on append l'emoji à la fin de la phrase.
    private func phraseRendu(segments: [SegmentNarration], finalise: Bool) -> AttributedString {
        let segmentsTraites = finalise ? segmentsSansPointFinal(segments) : segments

        var resultat = AttributedString("")
        resultat.font = .body

        var precedent: SegmentNarration?
        for segment in segmentsTraites {
            if besoinSeparateur(precedent: precedent, suivant: segment) {
                var sep = AttributedString(" ")
                sep.font = .body
                resultat.append(sep)
            }
            let estNeutre = segment.kind == "neutral"
            var segAttr = AttributedString(segment.text)
            segAttr.foregroundColor = couleur(pourType: segment.kind, faits: faits)
            segAttr.font = .body.weight(estNeutre ? .regular : .bold)
            resultat.append(segAttr)
            precedent = segment
        }

        if finalise {
            var emojiAttr = AttributedString(" \(emojiChoisi)")
            emojiAttr.font = .body
            resultat.append(emojiAttr)
        }

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
        case .chargement:
            return "Résumé de la journée en cours de génération."
        case .streaming(let s), .termine(let s):
            // Retire le placeholder `{emoji}` du label VoiceOver — il serait
            // sinon lu littéralement comme « accolade ouvrante e m o j i ... ».
            let texte = s.map(\.text).joined()
                .replacingOccurrences(of: "{emoji}", with: "")
            return "Résumé de la journée : " + texte
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
    /// Reflète l'état d'affichage du contenu de NarrationJourVue. Sert de
    /// déclencheur pour `.animation(_, value:)` posé sur la chaîne parent —
    /// c'est à ce niveau que vivent `.background` et `.glowIntelligence`.
    @State private var contenuVisible = false

    /// Forme partagée entre le `.background` (remplissage de carte) et le
    /// `.glowIntelligence` (contour stroké) : essentielle pour que le glow
    /// épouse exactement les bords de la carte.
    private var formeCarte: some InsettableShape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NarrationJourVue(faits: faits, contenuVisible: $contenuVisible)
                .id(compteur)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(formeCarte.fill(Color(.secondarySystemGroupedBackground)))
                .glowIntelligence(in: formeCarte)
                .animation(.smooth(duration: 0.4), value: contenuVisible)

            Button {
                compteur += 1
            } label: {
                Label(compteur == 0 ? "Générer" : "Régénérer", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        // Padding bumpé à 32pt pour que les couches floues du glow (jusqu'à
        // ~32pt de blur) ne soient pas rognées par les bords du fond.
        .padding(32)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Live — données excellentes") {
    PreviewBoutonGenerer(faits: .apercuExcellent)
}

#Preview("Live — données difficiles") {
    PreviewBoutonGenerer(faits: .apercuDifficile)
}
