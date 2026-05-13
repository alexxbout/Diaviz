//
//  SheetScoreMatin.swift
//  diaviz
//
//  Created by Alexandre on 13/05/2026.
//

import SwiftUI

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

    /// VM partagé avec `NarrationJourVue` — même prompt, même pipeline
    /// Foundation Models. On consomme `etat` pour rendre le texte, en
    /// ignorant la coloration sémantique des segments.
    @State private var modele = NarrationViewModel()

    /// `false` pendant le premier frame d'affichage, puis bascule à
    /// `true` au `.onAppear` pour déclencher le scale-in + fondu du
    /// cercle. Une seule transition par session de sheet.
    @State private var cercleApparu = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            titre

            Spacer(minLength: 0)

            cercleScore

            // Libellé qualitatif + date — bloc texte central.
            VStack(spacing: 6) {
                Text(libelleQualitatif)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text(dateFormatee)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.horizontal, 24)

            // Paragraphe d'analyse — rendu simple, sans couleur ni emoji.
            paragrapheAnalyse
                .padding(.horizontal, 24)

            Spacer(minLength: 0)

            boutonDetails
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .padding(.top, 20)
    }

    /// Grand cercle 170pt avec mesh gradient continu (rouge → vert selon
    /// le score) et chiffre du score en blanc 64pt bold centré. Ombre
    /// douce dans la teinte dominante. Animations à l'apparition :
    ///   - Scale 0.5 → 1.0 avec spring (réagit à `cercleApparu`).
    ///   - Opacity 0 → 1 (même transition).
    ///   - Chiffre interpolé de 0 au score final via `ChiffreAnime`.
    private var cercleScore: some View {
        ZStack {
            MeshScore.gradient(pour: faits.score)
                .clipShape(Circle())
                .frame(width: 170, height: 170)
                .shadow(
                    color: couleurAccent.opacity(0.40),
                    radius: 18,
                    x: 0,
                    y: 8
                )

            ChiffreAnime(cible: faits.score, duree: 1.8)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)
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
    /// du score, coin 14pt. Ferme la sheet au tap (les détails ne sont
    /// pas encore implémentés ; à brancher quand la vue détails existera).
    private var boutonDetails: some View {
        Button {
            dismiss()
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

// MARK: - Loader

/// Trois points qui pulsent pendant la génération. Local à ce fichier
/// pour éviter de coupler la sheet aux composants internes de
/// `NarrationJourVue` (qui a son propre indicateur, mais privé).
private struct LoaderPoints: View {
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
            }
        }
    }

    private func opacite(index: Int, date: Date) -> Double {
        let bucket = Int(date.timeIntervalSince1970 / 0.4) % 3
        return bucket == index ? 1.0 : 0.3
    }
}

// MARK: - Chiffre animé

/// Compteur simple qui grimpe de 0 à `cible` sur `duree` secondes, en
/// passant par toutes les valeurs intermédiaires. Pas d'effet visuel
/// particulier (ni blur, ni transition stylée) — juste le chiffre qui
/// change frame par frame.
///
/// Implémenté via `TimelineView(.animation)` qui re-évalue le contenu
/// à chaque frame (~60 Hz). On dérive le progrès du temps écoulé
/// depuis `debut`, on applique un easing `easeOut`, et on affiche
/// l'entier correspondant.
///
/// Délai 250 ms aligné sur le scale du cercle parent — les deux
/// animations démarrent au même instant après l'arrivée de la sheet.
private struct ChiffreAnime: View {
    let cible: Int
    let duree: TimeInterval

    @State private var debut: Date?

    var body: some View {
        TimelineView(.animation) { contexte in
            let progres: Double = {
                guard let debut else { return 0 }
                let t = contexte.date.timeIntervalSince(debut) / duree
                return min(1.0, max(0.0, t))
            }()
            // easeOut quadratique : 1 − (1 − x)² → départ rapide, fin douce.
            let eased = 1.0 - pow(1.0 - progres, 2.0)
            let valeur = Int((Double(cible) * eased).rounded())
            Text("\(valeur)")
                .monospacedDigit()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            debut = .now
        }
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

#Preview("Score 92 — Très bonne") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(faits: _faitsScore92, date: Date())
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}

#Preview("Score 78 — Bonne") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(faits: _faitsScore78, date: Date())
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}

#Preview("Score 58 — Moyenne") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(faits: _faitsScore58, date: Date())
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}

#Preview("Score 38 — Difficile") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(faits: _faitsScore38, date: Date())
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}

#Preview("Score 22 — Très difficile") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetScoreMatin(faits: _faitsScore22, date: Date())
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
}
