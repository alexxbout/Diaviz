//
//  EnTeteAnalyse.swift
//  diaviz
//

import SwiftUI

/// Carte de présentation posée en tête d'une page d'analyse : un dégradé
/// génératif grainé, le nom de l'analyse et une phrase qui dit ce qu'elle
/// observe.
///
/// **Aucun asset.** Une image aurait dû être déclinée en @2x/@3x, refaite pour
/// le mode clair et retouchée à chaque évolution de palette ; le dégradé, lui,
/// suit le thème et s'adapte à toutes les tailles. C'est aussi la grammaire
/// que l'app parle déjà avec le mesh de la carte de score.
///
/// **Pas de Liquid Glass** : le verre est la couche de chrome qui flotte
/// au-dessus du contenu (pilules, barres). Cette carte *est* du contenu — du
/// verre ici n'aurait rien à échantillonner et se lirait terne.
///
/// L'accroche reste **descriptive**, jamais un verdict : elle dit ce que la
/// page regarde, la conclusion appartient aux cartes qui suivent.
struct EnTeteAnalyse: View {

    /// Ambiance chromatique — une par analyse, pour que la page se reconnaisse
    /// à sa couleur avant même d'être lue.
    enum Ambiance {
        /// Tendance basale — indigo de nuit.
        case nuit
        /// Hypos au coucher — violet grenat.
        case coucher
        /// Détail du score — vert-jaune profond. Teinte **fixe** : elle ne
        /// suit pas la valeur du score, sinon la carte annoncerait le verdict
        /// avant qu'on l'ait lu.
        case score
        /// Écart de ratio (R1) — sarcelle profond.
        case ratio
        /// Glucides de la semaine — cuivre, la teinte que porte déjà la carte
        /// d'accueil correspondante.
        case glucides
        /// Bibliothèque — sépia d'encre, registre éditorial.
        case bibliotheque
        /// Inventaire du hub — vert d'eau. Ni un domaine de santé ni une
        /// analyse : la page décrit le contenu de l'app.
        case donnees
        /// Repas à revoir — vermillon. Même famille chaude que le cuivre des
        /// glucides, mais franchement plus saturé et plus clair : c'est
        /// l'écart de vivacité, pas la teinte, qui distingue les deux pages du
        /// domaine repas.
        case repasARevoir
        /// Charge d'activité — flamme ambrée, la teinte que porte déjà la
        /// carte d'accueil correspondante.
        case chargeActivite
        /// Corrections — bleu acier, froid comme le geste de la seringue :
        /// se distingue du sarcelle de R1 et de l'indigo nocturne de B1.
        case corrections

        /// Décale le motif de bruit d'une analyse à l'autre : deux cartes
        /// affichées l'une sous l'autre partageraient sinon exactement le même
        /// grain, ce que l'œil repère.
        var graineGrain: Float {
            switch self {
            case .nuit:         0
            case .coucher:      137
            case .score:        271
            case .ratio:        419
            case .glucides:     563
            case .bibliotheque: 701
            case .repasARevoir: 853
            case .donnees:      991
            case .chargeActivite: 1129
            case .corrections:    1277
            }
        }

        /// SF Symbol du badge — le sujet de la page, pas sa conclusion.
        var icone: String {
            switch self {
            case .nuit:         "moon.stars.fill"
            case .coucher:      "moon.zzz.fill"
            case .score:        "target"
            case .ratio:        "chart.dots.scatter"
            case .glucides:     "chart.bar.xaxis"
            case .bibliotheque: "books.vertical.fill"
            case .repasARevoir: "fork.knife"
            case .donnees:      "externaldrive.fill"
            case .chargeActivite: "flame.fill"
            case .corrections:    "syringe.fill"
            }
        }

        /// Cinq teintes, du fond le plus profond au halo le plus vif. Un
        /// dégradé linéaire à deux couleurs se lit comme un aplat ; ces cinq
        /// nuances réparties sur une grille donnent des courants de couleur
        /// qui ne se répètent pas, comme le mesh de la carte de score.
        ///
        /// Chaque teinte porte sa variante claire : en mode clair le dégradé
        /// ne s'éclaircit pas — il resterait sous le texte blanc — il change
        /// de valeur en gardant sa densité.
        var palette: (profond: Color, fond: Color, milieu: Color, halo: Color, second: Color) {
            switch self {
            case .nuit:
                (
                    Color(sombre: (0x0C, 0x12, 0x28), clair: (0x39, 0x40, 0x94)),
                    Color(sombre: (0x13, 0x1E, 0x3F), clair: (0x5B, 0x66, 0xC2)),
                    Color(sombre: (0x1D, 0x30, 0x65), clair: (0x7A, 0x84, 0xD4)),
                    Color(sombre: (0x68, 0x59, 0xCD), clair: (0x99, 0x91, 0xE8)),
                    Color(sombre: (0x35, 0x77, 0xC2), clair: (0x5F, 0x97, 0xDB))
                )
            case .coucher:
                (
                    Color(sombre: (0x21, 0x0C, 0x2A), clair: (0x51, 0x23, 0x64)),
                    Color(sombre: (0x3A, 0x15, 0x42), clair: (0x6C, 0x2A, 0x77)),
                    Color(sombre: (0x62, 0x21, 0x57), clair: (0x90, 0x38, 0x78)),
                    Color(sombre: (0xAE, 0x45, 0xCF), clair: (0xB2, 0x51, 0xC5)),
                    Color(sombre: (0xC1, 0x3A, 0x5D), clair: (0xBA, 0x41, 0x5F))
                )
            case .score:
                // Vert en bas, jaune en haut. Le jaune est monté dans le halo,
                // la teinte secondaire et le milieu, mais les deux tons les
                // plus profonds restent verts : c'est le rouge dans les
                // ombres qui produit l'olive, pas le jaune dans les lumières.
                (
                    Color(sombre: (0x0D, 0x2A, 0x18), clair: (0x18, 0x45, 0x2A)),
                    Color(sombre: (0x14, 0x40, 0x20), clair: (0x22, 0x5E, 0x33)),
                    Color(sombre: (0x33, 0x76, 0x2C), clair: (0x44, 0x88, 0x3A)),
                    Color(sombre: (0x8C, 0xD4, 0x40), clair: (0x88, 0xBC, 0x46)),
                    Color(sombre: (0xD2, 0xDE, 0x3E), clair: (0xC2, 0xCC, 0x4A))
                )
            case .ratio:
                // Jaune doré — même teinte que la carte accueil « Repas
                // dans le ratio » (`CarteAnalyseRatio`). Indigo, teal/mint
                // et rose vif essayés puis écartés (déjà pris, ou pas au
                // goût).
                (
                    Color(sombre: (0x24, 0x1A, 0x04), clair: (0x54, 0x3E, 0x0C)),
                    Color(sombre: (0x3C, 0x2C, 0x08), clair: (0x7C, 0x5C, 0x14)),
                    Color(sombre: (0x5C, 0x44, 0x0C), clair: (0xA6, 0x80, 0x20)),
                    Color(sombre: (0x8C, 0x68, 0x14), clair: (0xCE, 0xA6, 0x30)),
                    Color(sombre: (0xB0, 0x86, 0x20), clair: (0xE6, 0xBC, 0x44))
                )
            case .glucides:
                (
                    Color(sombre: (0x26, 0x17, 0x0C), clair: (0x69, 0x3E, 0x22)),
                    Color(sombre: (0x41, 0x25, 0x13), clair: (0x84, 0x51, 0x2B)),
                    Color(sombre: (0x63, 0x39, 0x1D), clair: (0xAA, 0x6D, 0x3C)),
                    Color(sombre: (0xB0, 0x6F, 0x37), clair: (0xC0, 0x84, 0x4A)),
                    Color(sombre: (0x87, 0x46, 0x46), clair: (0xAB, 0x61, 0x52))
                )
            case .bibliotheque:
                (
                    Color(sombre: (0x1C, 0x17, 0x13), clair: (0x4D, 0x40, 0x34)),
                    Color(sombre: (0x31, 0x28, 0x20), clair: (0x65, 0x54, 0x44)),
                    Color(sombre: (0x4C, 0x3E, 0x30), clair: (0x86, 0x73, 0x5E)),
                    Color(sombre: (0x8C, 0x73, 0x54), clair: (0xA0, 0x8A, 0x6F)),
                    Color(sombre: (0x5F, 0x52, 0x73), clair: (0x7C, 0x70, 0x95))
                )
            case .repasARevoir:
                (
                    Color(sombre: (0x28, 0x08, 0x0C), clair: (0x6B, 0x1C, 0x1A)),
                    Color(sombre: (0x45, 0x0E, 0x12), clair: (0x8E, 0x2C, 0x22)),
                    Color(sombre: (0x78, 0x1C, 0x16), clair: (0xB6, 0x44, 0x2A)),
                    Color(sombre: (0xE8, 0x5A, 0x2E), clair: (0xDD, 0x6E, 0x3E)),
                    Color(sombre: (0xCE, 0x2E, 0x3E), clair: (0xC8, 0x44, 0x4A))
                )
            case .donnees:
                // Indigo — remplace l'ancien vert/teal, trop proche de la
                // carte « Médications » du Journal (déjà verte).
                (
                    Color(sombre: (0x14, 0x10, 0x2E), clair: (0x2E, 0x25, 0x66)),
                    Color(sombre: (0x1E, 0x18, 0x44), clair: (0x3C, 0x30, 0x82)),
                    Color(sombre: (0x30, 0x26, 0x68), clair: (0x50, 0x42, 0xA8)),
                    Color(sombre: (0x4A, 0x3D, 0x9E), clair: (0x66, 0x58, 0xC4)),
                    Color(sombre: (0x5A, 0x4E, 0xB0), clair: (0x74, 0x68, 0xD2))
                )
            case .chargeActivite:
                // Ambre/flamme — même famille chaude que les glucides et
                // repas à revoir, mais orange franc plutôt que cuivre ou
                // vermillon : la teinte que porte déjà `CarteChargeActivite`.
                (
                    Color(sombre: (0x28, 0x16, 0x04), clair: (0x6E, 0x3F, 0x0A)),
                    Color(sombre: (0x45, 0x25, 0x06), clair: (0x8F, 0x54, 0x0C)),
                    Color(sombre: (0x7A, 0x42, 0x0A), clair: (0xB8, 0x71, 0x18)),
                    Color(sombre: (0xE8, 0x8A, 0x1E), clair: (0xE0, 0x91, 0x2E)),
                    Color(sombre: (0xD9, 0x52, 0x1E), clair: (0xD1, 0x5C, 0x2A))
                )
            case .corrections:
                // Bleu roi profond — froid comme le geste de la seringue,
                // sans virer au cyan clair (trop pâle) ni à l'acier terne
                // (premier jet). Halo saturé mais sombre, à l'opposé
                // chromatique du vermillon des repas à revoir et de l'ambre
                // de la charge d'activité.
                (
                    Color(sombre: (0x04, 0x0C, 0x22), clair: (0x0C, 0x1C, 0x42)),
                    Color(sombre: (0x08, 0x16, 0x3C), clair: (0x11, 0x2A, 0x60)),
                    Color(sombre: (0x0C, 0x28, 0x6E), clair: (0x16, 0x42, 0x9C)),
                    Color(sombre: (0x1A, 0x48, 0xE8), clair: (0x1E, 0x4C, 0xD8)),
                    Color(sombre: (0x2C, 0x30, 0xA0), clair: (0x30, 0x38, 0x98))
                )
            }
        }
    }

    /// Le grain est plus discret en mode clair : sur un fond lumineux, la
    /// même amplitude se lit comme de la saleté plutôt que comme une matière.
    @Environment(\.colorScheme) private var colorScheme

    var surtitre: String? = nil
    let titre: String
    let accroche: String
    let ambiance: Ambiance

    /// Hauteur minimale — le contenu peut la dépasser en gros corps de texte,
    /// jamais l'inverse : une carte qui rétrécit casserait le rythme des pages
    /// entre elles.
    private static let hauteurMinimale: CGFloat = 148

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            fond
            contenu
        }
        .frame(maxWidth: .infinity, minHeight: Self.hauteurMinimale, alignment: .bottomLeading)
        .clipShape(NiveauCarte.carte.forme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([surtitre, titre, accroche].compactMap { $0 }.joined(separator: ". "))
    }

    private var fond: some View {
        let p = ambiance.palette
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                // Grille volontairement irrégulière : une grille droite
                // produit des bandes horizontales, un point décalé suffit à
                // faire couler la couleur en diagonale.
                .init(0.00, 0.00), .init(0.55, 0.00), .init(1.00, 0.00),
                .init(0.00, 0.45), .init(0.38, 0.58), .init(1.00, 0.38),
                .init(0.00, 1.00), .init(0.62, 1.00), .init(1.00, 1.00),
            ],
            colors: [
                p.halo,    p.milieu, p.second,
                p.milieu,  p.fond,   p.milieu,
                p.fond,    p.profond, p.fond,
            ],
            colorSpace: .perceptual
        )
        // Grain appliqué **au dégradé**, pas en calque au-dessus : le shader
        // reçoit la couleur déjà rendue et la fait varier pixel par pixel.
        // Un calque d'image tuilée trahissait sa trame sur les grandes
        // largeurs et changeait de densité selon l'échelle de l'écran.
        .colorEffect(
            ShaderLibrary.grainDiaviz(
                // Amplitude assumée : le grain doit se voir comme une
                // matière, pas se deviner. Le bruit reste centré sur zéro,
                // donc il ne change pas la luminosité moyenne du dégradé et
                // le texte blanc garde son contraste.
                .float(colorScheme == .dark ? 0.22 : 0.15),
                .float(ambiance.graineGrain)
            )
        )
    }

    /// Badge en haut, titre et accroche en bas — le `Spacer` les repousse
    /// chacun vers son bord. Les trois étaient auparavant collés au bas de la
    /// carte, ce qui laissait la moitié haute du dégradé vide et resserrait
    /// tout le texte sur quelques points de hauteur.
    private var contenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let surtitre {
                badge(surtitre)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(titre)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                Text(accroche)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    /// Capsule en **Liquid Glass**, seul élément de la carte qui s'y prête :
    /// elle flotte au-dessus du dégradé — donc au-dessus de contenu, l'usage
    /// exact du matériau — et va y échantillonner ses couleurs, ce qu'un voile
    /// blanc à opacité fixe ne sait pas faire. Le reste de la carte reste du
    /// contenu, et le contenu ne se pose pas sur du verre.
    private func badge(_ libelle: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ambiance.icone)
                .font(.caption2.weight(.semibold))
            Text(libelle)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Couleur adaptative

private extension Color {

    /// Couleur définie par ses composantes sombres **et** claires — le texte
    /// posé dessus reste blanc dans les deux thèmes, le dégradé doit donc
    /// garder sa densité en mode clair plutôt que de s'éclaircir.
    init(sombre: (Int, Int, Int), clair: (Int, Int, Int)) {
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? sombre : clair
            return UIColor(
                red: CGFloat(c.0) / 255,
                green: CGFloat(c.1) / 255,
                blue: CGFloat(c.2) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Les deux analyses") {
    ScrollView {
        VStack(spacing: 12) {
            EnTeteAnalyse(
                surtitre: "Analyse du coucher",
                titre: "Tendance basale",
                accroche: "La pente de vos nuits profondes, mesurée depuis votre prise de lente.",
                ambiance: .nuit
            )
            EnTeteAnalyse(
                surtitre: "Analyse du coucher",
                titre: "Hypos au coucher",
                accroche: "Ce qui suit vos soirées, selon la façon dont elles commencent.",
                ambiance: .coucher
            )
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Mode clair") {
    ScrollView {
        VStack(spacing: 12) {
            EnTeteAnalyse(titre: "Tendance basale", accroche: "14 nuits analysées, zone 3 ancrée sur votre lente.", ambiance: .nuit)
            EnTeteAnalyse(titre: "Hypos au coucher", accroche: "Ce qui suit vos soirées, selon la façon dont elles commencent.", ambiance: .coucher)
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.light)
}

#Preview("Texte agrandi") {
    ScrollView {
        EnTeteAnalyse(
            surtitre: "Analyse du coucher",
            titre: "Tendance basale",
            accroche: "La pente de vos nuits profondes, mesurée depuis votre prise de lente.",
            ambiance: .nuit
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
