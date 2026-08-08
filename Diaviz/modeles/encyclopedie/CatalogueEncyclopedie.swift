//
//  CatalogueEncyclopedie.swift
//  diaviz
//

import Foundation

/// Contenu de la bibliothèque, figé dans le binaire.
///
/// Chaque fiche synthétise ce que la littérature établit sur un point
/// précis, et cite ses sources. **Formulation au constat** (« les études
/// observent que… »), jamais à l'impératif : ces fiches documentent, elles
/// ne prescrivent pas, et ne connaissent rien des données de l'utilisateur.
///
/// Alimenté au fur et à mesure des analyses construites — les fiches
/// actuelles viennent du cadrage de S1 (réponse glycémique au sport).
enum CatalogueEncyclopedie {

    static var fiches: [FicheEncyclopedie] {
        [
            gri, tempsDansCible, ciblesConsensusTir, gmiVsHbA1c,
            glucidesPendantEffort, seuilsDemarrage,
            hypoRetardee, compressionLows, alcoolHypoRetardee,
            resucrageHypo, cetones
        ]
    }

    static func fiches(du theme: ThemeEncyclopedie) -> [FicheEncyclopedie] {
        fiches.filter { $0.theme == theme }
    }

    // MARK: - Sources partagées

    private static let ispad = SourceEncyclopedie(
        titre: "ISPAD Clinical Practice Consensus Guidelines 2022 — Exercise",
        reference: "Adolfsson et al., Pediatric Diabetes, 2022",
        url: URL(string: "https://onlinelibrary.wiley.com/doi/10.1111/pedi.13452")
    )

    private static let riddell = SourceEncyclopedie(
        titre: "Exercise management in type 1 diabetes: a consensus statement",
        reference: "Riddell et al., Lancet Diabetes & Endocrinology, 2017",
        url: URL(string: "https://www.thelancet.com/article/S2213-8587(17)30014-1/abstract")
    )

    private static let recuperation = SourceEncyclopedie(
        titre: "Post-exercise recovery for the endurance athlete with type 1 diabetes",
        reference: "Lancet Diabetes & Endocrinology, 2021",
        url: URL(string: "https://www.thelancet.com/journals/landia/article/PIIS2213-8587(21)00054-1/abstract")
    )

    private static let hypoExercice = SourceEncyclopedie(
        titre: "Exercise, Hypoglycemia, and Type 1 Diabetes",
        reference: "Diabetes Technology & Therapeutics",
        url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC4029043/")
    )

    private static let t1dexi = SourceEncyclopedie(
        titre: "Factors Associated With Nocturnal Hypoglycemia After Exercise (T1DEXI)",
        reference: "Diabetes Care, American Diabetes Association",
        url: URL(string: "https://diabetesjournals.org/care/article-abstract/doi/10.2337/dc26-0381/170105/Factors-Associated-With-Nocturnal-Hypoglycemia")
    )

    private static let klonoff = SourceEncyclopedie(
        titre: "A Glycemia Risk Index (GRI) of Hypoglycemia and Hyperglycemia for CGM, Validated by Clinician Ratings",
        reference: "Klonoff et al., Journal of Diabetes Science and Technology, 2022",
        url: URL(string: "https://journals.sagepub.com/doi/10.1177/19322968221085273")
    )

    private static let variabiliteGri = SourceEncyclopedie(
        titre: "Impact of glucose variability on the assessment of the glycemia risk index and classic glycemic metrics",
        reference: "Frontiers in Endocrinology",
        url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC10618378/")
    )

    private static let consensusCgm = SourceEncyclopedie(
        titre: "Understanding the Glycemia Risk Index for CGM data interpretation",
        reference: "ADCES / danatech",
        url: URL(string: "https://www.adces.org/education/danatech/glucose-monitoring/continuous-glucose-monitors-(cgm)/glycemic-metrics--an-overview/using-gri-to-deepen-glycemic-data-interpretation")
    )

    private static let battelinoTir = SourceEncyclopedie(
        titre: "Clinical Targets for Continuous Glucose Monitoring Data Interpretation: Recommendations From the International Consensus on Time in Range",
        reference: "Battelino et al., Diabetes Care, 2019",
        url: URL(string: "https://diabetesjournals.org/care/article/42/8/1593/36184/Clinical-Targets-for-Continuous-Glucose-Monitoring")
    )

    private static let gmiTimeToChange = SourceEncyclopedie(
        titre: "The Glucose Management Indicator: Time to Change Course?",
        reference: "American Diabetes Association, Diabetes Care, 2024",
        url: URL(string: "https://diabetesjournals.org/care/article/47/6/906/154177/The-Glucose-Management-Indicator-Time-to-Change")
    )

    private static let gmiPediatriqueT1D = SourceEncyclopedie(
        titre: "Discordance between Glucose Management Indicator and Glycated Hemoglobin in a Pediatric Cohort with Type 1 Diabetes: A Real-World Study",
        reference: "PMC, 2026",
        url: URL(string: "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10887365/")
    )

    private static let pisaModelisation = SourceEncyclopedie(
        titre: "Modeling Transient Disconnections and Compression Artifacts of Continuous Glucose Sensors",
        reference: "Littérature technique CGM — caractérisation des PISA (Pressure-Induced Sensor Attenuations)",
        url: URL(string: "https://www.researchgate.net/publication/294897270_Modeling_Transient_Disconnections_and_Compression_Artifacts_of_Continuous_Glucose_Sensors")
    )

    private static let pisaDetection = SourceEncyclopedie(
        titre: "Detection of compression artifacts in time-series data from continuous glucose monitoring sensors using matched filters",
        reference: "IEEE, 2026",
        url: URL(string: "https://ieeexplore.ieee.org/document/10331579/")
    )

    private static let alcoolMatinSuivant = SourceEncyclopedie(
        titre: "The Effect of Evening Alcohol Consumption on Next-Morning Glucose Control in Type 1 Diabetes",
        reference: "Diabetes Care, American Diabetes Association, 2001",
        url: URL(string: "https://diabetesjournals.org/care/article/24/11/1888/24724/The-Effect-of-Evening-Alcohol-Consumption-on-Next")
    )

    private static let alcoolRevueSystematique = SourceEncyclopedie(
        titre: "Effects of alcohol on blood glucose levels in people with type 1 diabetes: A systematic review",
        reference: "Journal of Diabetes Nursing",
        url: URL(string: "https://diabetesonthenet.com/journal-diabetes-nursing/effects-of-alcohol-on-blood-glucose-levels-in-people-with-type-1-diabetes-a-systematic-review/")
    )

    // MARK: - Fiches

    private static var gri: FicheEncyclopedie {
        .init(
            id: "gri",
            titre: "Le score quotidien (GRI)",
            resume: "Un indice unique qui pèse plus lourdement les hypoglycémies",
            icone: "target",
            theme: .mesure,
            sections: [
                .init(
                    titre: "Ce qu'il mesure",
                    texte: "Le Glycemia Risk Index résume en un seul nombre la qualité de l'équilibre glycémique sur une période. Il ne retient que quatre variables, celles jugées cliniquement actionnables par les auteurs : les proportions de temps passées en zone très basse, basse, haute et très haute. Le temps passé en cible n'entre pas directement dans la formule — c'est le hors-cible qui est compté."
                ),
                .init(
                    titre: "La formule",
                    texte: "Chaque zone hors-cible est pondérée par un coefficient. Les zones basses pèsent nettement plus lourd que les zones hautes, à durée égale : passer dix minutes sous 54 mg/dL dégrade davantage l'indice qu'une même durée au-dessus de 250.",
                    points: [
                        "3,0 × pourcentage de temps sous 54 mg/dL",
                        "2,4 × pourcentage de temps entre 54 et 69 mg/dL",
                        "1,6 × pourcentage de temps au-dessus de 250 mg/dL",
                        "0,8 × pourcentage de temps entre 181 et 250 mg/dL"
                    ]
                ),
                .init(
                    titre: "Comment Diaviz l'affiche",
                    texte: "Le GRI est un indice de risque : plus il est élevé, plus la période est dégradée. L'application affiche son complément sur 100 — le score montré sur l'accueil vaut 100 moins le GRI, borné entre 0 et 100. Un score élevé correspond donc à une bonne période, ce qui se lit plus naturellement qu'un indice de risque brut."
                ),
                .init(
                    titre: "Pourquoi cet indice plutôt qu'un autre",
                    texte: "L'étude de validation rapporte une corrélation élevée entre le GRI et le classement de qualité glycémique établi par des cliniciens à partir des mêmes tracés. Les auteurs relèvent que les indicateurs plus anciens — HbA1c et temps dans la cible — corrèlent mal, voire pas du tout, avec les paramètres d'hypoglycémie. C'est ce qui distingue le GRI : il ne laisse pas les hypoglycémies invisibles derrière une bonne moyenne.",
                    points: [
                        "Corrélation avec l'évaluation de cliniciens : r = 0,95",
                        "Validé sur des tracés de mesure continue du glucose",
                        "Publié en 2022, revue Journal of Diabetes Science and Technology"
                    ]
                ),
                .init(
                    titre: "Ses limites",
                    texte: "Le GRI dépend de la couverture du capteur : calculé sur une journée trouée, il perd son sens, ce qui explique que l'application n'affiche aucun score en dessous de 70 % de couverture. Des travaux ultérieurs relèvent par ailleurs que la variabilité glycémique influence l'indice, et qu'un même score peut recouvrir des profils de journée assez différents."
                )
            ],
            sources: [klonoff, variabiliteGri, consensusCgm],
            analysesLiees: ["Score quotidien — accueil"]
        )
    }

    private static var tempsDansCible: FicheEncyclopedie {
        .init(
            id: "temps-dans-cible",
            titre: "Temps dans la cible",
            resume: "L'indicateur de référence, et ce qu'il ne montre pas",
            icone: "chart.line.flattrend.xyaxis",
            theme: .mesure,
            sections: [
                .init(
                    titre: "Ce qu'il mesure",
                    texte: "Le temps dans la cible correspond à la proportion de mesures situées dans l'intervalle de référence, le plus souvent 70 à 180 mg/dL. C'est l'indicateur le plus répandu pour lire un tracé de mesure continue, parce qu'il se comprend immédiatement et se compare d'une période à l'autre."
                ),
                .init(
                    titre: "Son angle mort",
                    texte: "Deux journées affichant le même temps dans la cible peuvent correspondre à des situations très différentes : l'une passée juste au-dessus de la cible, l'autre alternant hypoglycémies et hyperglycémies. Les travaux de validation du GRI relèvent que le temps dans la cible corrèle mal avec les paramètres d'hypoglycémie — c'est précisément ce qui a motivé la construction d'un indice pondéré."
                )
            ],
            sources: [klonoff, consensusCgm],
            analysesLiees: ["Score quotidien — accueil"]
        )
    }

    private static var ciblesConsensusTir: FicheEncyclopedie {
        .init(
            id: "cibles-consensus-tir",
            titre: "Cibles du consensus international (Time in Range)",
            resume: "Les seuils sur lesquels repose le 70-180 mg/dL utilisé partout dans l'app",
            icone: "checkmark.seal.fill",
            theme: .mesure,
            sections: [
                .init(
                    titre: "D'où vient l'intervalle 70-180 mg/dL",
                    texte: "Le consensus international sur le temps dans la cible, réuni par un groupe d'experts en 2019, fixe la plage de référence à 70-180 mg/dL pour le diabète de type 1 et de type 2. C'est cet intervalle que Diaviz reprend tel quel pour classer les repas, les nuits et le score quotidien — pas une convention interne."
                ),
                .init(
                    titre: "Les cibles de temps associées",
                    texte: "Le consensus ne se limite pas à définir la plage : il propose des seuils de temps par catégorie, pensés comme des repères généraux pour la population adulte hors grossesse, pas comme des objectifs personnalisés.",
                    points: [
                        "Temps dans la cible (70-180 mg/dL) : plus de 70 % du temps",
                        "Temps sous 70 mg/dL : moins de 4 % du temps",
                        "Temps sous 54 mg/dL : moins de 1 % du temps",
                        "Temps au-dessus de 180 mg/dL : moins de 25 % du temps",
                        "Temps au-dessus de 250 mg/dL : moins de 5 % du temps"
                    ]
                ),
                .init(
                    titre: "Portée de ces chiffres",
                    texte: "Le consensus précise lui-même que ces cibles sont des repères de population, à ajuster selon l'âge, la grossesse ou le risque d'hypoglycémie sévère. Ce sont des points de comparaison généraux, pas des seuils que l'app applique à qui que ce soit individuellement."
                )
            ],
            sources: [battelinoTir],
            analysesLiees: ["Score quotidien — accueil", "R1 — Réponse glycémique post-repas"]
        )
    }

    private static var gmiVsHbA1c: FicheEncyclopedie {
        .init(
            id: "gmi-vs-hba1c",
            titre: "GMI et HbA1c : deux mesures, pas toujours d'accord",
            resume: "Pourquoi le chiffre du capteur peut différer de la prise de sang",
            icone: "arrow.left.arrow.right",
            theme: .mesure,
            sections: [
                .init(
                    titre: "Deux origines différentes",
                    texte: "Le Glucose Management Indicator (GMI) est une estimation de l'HbA1c calculée à partir de la glycémie moyenne mesurée par le capteur, dans le liquide interstitiel. L'HbA1c mesurée en laboratoire vient, elle, directement du sang. Les deux visent la même chose — une estimation de l'équilibre glycémique sur plusieurs semaines — par deux voies différentes.",
                    points: ["Formule : GMI (%) = 3,31 + 0,02392 × glycémie moyenne (mg/dL)"]
                ),
                .init(
                    titre: "L'écart observé",
                    texte: "Les études rapportent un écart absolu typique de 0,6 à 0,65 point entre les deux mesures, avec des variations plus marquées chez certains profils. L'écart tend à augmenter avec une plus grande variabilité glycémique et un temps au-dessus de la cible plus élevé — deux éléments qui peuvent faire diverger la glycémie moyenne interstitielle de la glycation réelle de l'hémoglobine."
                ),
                .init(
                    titre: "Ce que ça veut dire pour la lecture des chiffres",
                    texte: "Un score ou une moyenne calculée par Diaviz à partir du capteur ne remplace pas l'HbA1c du bilan sanguin, et un désaccord entre les deux n'est pas anormal en soi : ce sont deux mesures distinctes, pas la même grandeur vue deux fois."
                )
            ],
            sources: [gmiTimeToChange, gmiPediatriqueT1D],
            analysesLiees: ["Score quotidien — accueil"]
        )
    }

    private static var glucidesPendantEffort: FicheEncyclopedie {
        .init(
            id: "glucides-effort",
            titre: "Glucides pendant l'effort",
            resume: "Le besoin dépend autant de l'insuline active que de la durée",
            icone: "fork.knife",
            theme: .sport,
            sections: [
                .init(
                    titre: "Deux facteurs, pas un",
                    texte: "Les besoins glucidiques observés pendant un effort dépendent de sa durée, mais aussi — et dans des proportions comparables — de la quantité d'insuline encore active au départ. À durée égale, le besoin peut varier du simple au double selon ce paramètre.",
                    points: [
                        "30 à 60 min, peu d'insuline active : 10 à 15 g en aérobie modérée, 10 à 20 g en effort intense",
                        "30 à 60 min, beaucoup d'insuline active : 15 à 30 g toutes les 30 min",
                        "60 à 150 min, peu d'insuline active : 30 à 60 g par heure",
                        "60 à 150 min, beaucoup d'insuline active : jusqu'à 75 g par heure"
                    ]
                ),
                .init(
                    titre: "Prises répétées plutôt qu'une charge unique",
                    texte: "Les protocoles décrits reposent sur de petites quantités répétées toutes les 20 à 30 minutes, selon la fréquence de contrôle glycémique, plutôt que sur une prise unique au départ. Cette approche vise à limiter à la fois l'hypoglycémie pendant l'effort et l'hyperglycémie de rebond."
                ),
                .init(
                    titre: "Sur le choix du type de glucide",
                    texte: "Les sources justifient le choix entre glucides à index élevé et plus lents par la fréquence de contrôle : un contrôle rapproché rend les glucides rapides plus efficaces, un contrôle espacé tolère mieux des glucides lents pour éviter un rebond. Aucune de ces sources ne relie ce choix à la durée de l'effort — l'idée qu'un glucide lent tiendrait mieux sur la distance reste, à ce jour, une hypothèse non démontrée en diabète de type 1."
                ),
                .init(
                    titre: "Type d'effort",
                    texte: "Les études distinguent trois régimes. L'aérobie continu entraîne la baisse glycémique la plus marquée et le besoin glucidique le plus élevé. L'anaérobie et les efforts très intenses tendent au contraire à faire monter la glycémie, avec peu ou pas de besoin supplémentaire. Les efforts mixtes, par intervalles, se situent entre les deux avec une baisse moindre qu'en aérobie pur."
                )
            ],
            sources: [riddell, ispad],
            analysesLiees: ["S1 — Réponse glycémique sport"]
        )
    }

    private static var seuilsDemarrage: FicheEncyclopedie {
        .init(
            id: "seuils-demarrage",
            titre: "Glycémie au démarrage d'un effort",
            resume: "Une fourchette de sécurité large, pas une cible personnelle",
            icone: "flag.checkered",
            theme: .sport,
            sections: [
                .init(
                    titre: "L'intervalle décrit",
                    texte: "Les consensus décrivent une fourchette de départ de 126 à 250 mg/dL, avec une glycémie stable et des cétones basses. Cet intervalle est large parce qu'il doit couvrir tous les types d'effort et tous les profils : il ne constitue pas une cible individuelle.",
                    points: [
                        "Sous 90 mg/dL : 10 à 20 g de glucose avant de démarrer",
                        "Entre 90 et 126 mg/dL : 10 g suffisent d'après les mêmes sources",
                        "La borne haute de référence chez l'adulte est 250 mg/dL"
                    ]
                ),
                .init(
                    titre: "Sur la borne haute",
                    texte: "Certaines sources pédiatriques mentionnent 270 mg/dL comme limite de tolérance. Il s'agit d'un plafond de sécurité, pas d'une valeur recommandée pour démarrer : au-delà de 250 mg/dL, le risque cétonique augmente et les consensus adultes retiennent cette borne plus basse."
                )
            ],
            sources: [riddell, ispad],
            analysesLiees: ["S1 — Réponse glycémique sport"]
        )
    }

    private static var hypoRetardee: FicheEncyclopedie {
        .init(
            id: "hypo-retardee",
            titre: "Hypoglycémie retardée après l'effort",
            resume: "Le risque s'étend bien au-delà de la séance, jusqu'à la nuit suivante",
            icone: "clock.arrow.circlepath",
            theme: .nuit,
            sections: [
                .init(
                    titre: "Une fenêtre longue",
                    texte: "L'effort augmente la sensibilité à l'insuline pour une durée qui dépasse largement la séance elle-même. Les mesures montrent un besoin en glucose accru plusieurs heures après, et une majorité d'épisodes survenant le lendemain.",
                    points: [
                        "Besoin en glucose démontré 7 à 11 h après un effort d'après-midi",
                        "Majorité des épisodes observés 15 à 24 h après la séance",
                        "Sensibilité à l'insuline élevée pendant 24 à 48 h",
                        "Effet d'autant plus marqué que l'effort a été intense et prolongé"
                    ]
                ),
                .init(
                    titre: "Facteurs associés à un risque moindre",
                    texte: "Les analyses de cohorte identifient plusieurs facteurs associés à un risque réduit d'hypoglycémie nocturne après un effort.",
                    points: [
                        "Glycémie plus élevée avant l'effort et au coucher",
                        "Absence d'hypoglycémie pendant l'effort ou dans les 4 h qui suivent",
                        "Moins de temps passé sous la cible avant l'effort"
                    ]
                )
            ],
            sources: [t1dexi, recuperation, hypoExercice],
            analysesLiees: [
                "B1 — Détection basale",
                "B2 — Hypos au coucher",
                "S1 — Réponse glycémique sport"
            ]
        )
    }

    private static var compressionLows: FicheEncyclopedie {
        .init(
            id: "compression-lows",
            titre: "Fausses hypos par compression du capteur",
            resume: "Une chute brutale et isolée la nuit n'est pas toujours une vraie hypo",
            icone: "bed.double.fill",
            theme: .nuit,
            sections: [
                .init(
                    titre: "Le mécanisme",
                    texte: "Une pression mécanique sur le capteur — dormir dessus, par exemple — peut réduire localement le flux de liquide interstitiel autour du site d'insertion et faire chuter artificiellement la valeur lue. La littérature technique nomme ce phénomène PISA (Pressure-Induced Sensor Attenuation)."
                ),
                .init(
                    titre: "Sa signature",
                    texte: "L'artefact se reconnaît à une chute brutale en V, sans les signes physiques d'une vraie hypoglycémie, qui se résorbe rapidement dès que la pression est relâchée — un changement de position, par exemple. Il survient plus fréquemment la nuit, la position allongée favorisant l'appui prolongé sur le capteur."
                ),
                .init(
                    titre: "Pourquoi c'est pertinent pour la lecture d'une nuit",
                    texte: "Une chute isolée en V étroit sur une courbe autrement stable peut donc être un artefact de capteur plutôt qu'un événement glycémique réel — une distinction que les fiches de nuit et d'endormissement de l'app ne font pas encore automatiquement aujourd'hui."
                )
            ],
            sources: [pisaModelisation, pisaDetection],
            analysesLiees: ["B1 — Détection basale", "B2 — Hypos au coucher"]
        )
    }

    private static var alcoolHypoRetardee: FicheEncyclopedie {
        .init(
            id: "alcool-hypo-retardee",
            titre: "Alcool et hypoglycémie retardée",
            resume: "Un verre le soir peut se répercuter sur la glycémie du lendemain matin",
            icone: "wineglass.fill",
            theme: .nuit,
            sections: [
                .init(
                    titre: "Le mécanisme",
                    texte: "Le foie priorise le métabolisme de l'alcool sur la production de glucose : la néoglucogenèse hépatique est inhibée pendant que l'organisme traite l'alcool, et les réserves de glycogène se vident plus vite. Cet effet s'ajoute à celui de l'insuline déjà injectée, sans mécanisme de compensation hépatique disponible."
                ),
                .init(
                    titre: "Une fenêtre qui dépasse la soirée",
                    texte: "Les études rapportent un risque d'hypoglycémie pouvant survenir jusqu'à 12 h après la consommation. Une étude princeps montre qu'une consommation modérée en soirée est associée à une dégradation du contrôle glycémique le lendemain matin, avec une sécrétion nocturne d'hormone de croissance réduite."
                ),
                .init(
                    titre: "Contre-régulation affaiblie",
                    texte: "L'alcool atténue aussi la réponse hormonale de contre-régulation à l'hypoglycémie — adrénaline, glucagon, cortisol, hormone de croissance — ce qui peut à la fois retarder la détection d'une chute et ralentir la remontée spontanée."
                )
            ],
            sources: [alcoolMatinSuivant, alcoolRevueSystematique],
            analysesLiees: ["B1 — Détection basale"]
        )
    }

    private static var resucrageHypo: FicheEncyclopedie {
        .init(
            id: "resucrage-hypo",
            titre: "Resucrage et supplémentation préventive",
            resume: "Deux gestes distincts, souvent confondus",
            icone: "cross.case.fill",
            theme: .hypoglycemie,
            sections: [
                .init(
                    titre: "Traiter une hypoglycémie",
                    texte: "En dessous de 54 mg/dL, les recommandations décrivent l'arrêt de l'activité, un traitement par glucides à index élevé, et l'absence de reprise tant que la glycémie n'est pas remontée. Entre 72 et 88 mg/dL pendant un effort, un report ou une interruption d'une vingtaine de minutes est décrit."
                ),
                .init(
                    titre: "Prévenir une chute — un geste différent",
                    texte: "Distincte du traitement d'une hypoglycémie déclarée, la supplémentation préventive intervient avant, alors que la glycémie est encore correcte mais orientée à la baisse. Les protocoles la décrivent dès 126 mg/dL en cas de tendance descendante, par petites quantités répétées.",
                    points: [
                        "Doses de 8 à 20 g, soit environ 0,2 à 0,5 g par kilo de poids",
                        "Répétées toutes les 20 à 30 min selon la fréquence de contrôle",
                        "Quantité augmentée entre 90 et 124 mg/dL"
                    ]
                ),
                .init(
                    titre: "Pourquoi la distinction compte",
                    texte: "Ces deux gestes n'ont ni le même déclencheur, ni le même objectif, ni la même quantité. Les confondre dans une même statistique ne mesure rien — c'est la raison pour laquelle Diaviz demande de déclarer l'intention au moment de la saisie."
                )
            ],
            sources: [ispad, riddell],
            analysesLiees: ["S1 — Réponse glycémique sport"]
        )
    }

    private static var cetones: FicheEncyclopedie {
        .init(
            id: "cetones",
            titre: "Cétones et effort",
            resume: "Le seul point où la littérature est catégorique",
            icone: "exclamationmark.triangle.fill",
            theme: .sport,
            sections: [
                .init(
                    titre: "Ce que les sources établissent",
                    texte: "L'exercice pratiqué en présence de cétones expose à un risque d'acidocétose, complication aiguë nécessitant une prise en charge médicale. C'est le point sur lequel les recommandations sont les plus nettes, sans nuance selon le type d'effort.",
                    points: [
                        "Ne pas démarrer d'effort avec des cétones positives",
                        "Au-delà de 350 mg/dL, un contrôle des cétones est décrit",
                        "L'effort en hyperglycémie marquée peut aggraver la production de cétones"
                    ]
                )
            ],
            sources: [ispad, riddell],
            analysesLiees: []
        )
    }
}
