# Cartes d'insights accueil — « Nouvelles tendances »

> Section en tête de l'accueil (`SectionInsights` → `PileVerticaleInsights`) : une pile de cartes courtes qui signalent ce qui vient de se produire ou de devenir consultable. Toujours factuel, jamais une dose recommandée.

**Statut** : 🟢 Livré — une alerte, deux cartes d'état et six cartes d'événement. Aucun plafond.
**Fichiers** : `Diaviz/modeles/insights/Insight.swift` (modèle, destinations, courbe), `Diaviz/services/derivation/CalculInsightsEvenements.swift` (cartes d'événement, durées de vie, ordre), `Diaviz/vues/accueil/Insights/` (pile, carte, micro-visuels, `CourbeInsightVue`), `Diaviz/vues/accueil/AccueilVue.swift` (assemblage, destinations, suppressions), `DiavizTests/CalculInsightsEvenementsTests.swift`.

---

## Pourquoi
- Une observation factuelle courte doit pouvoir remonter sur l'accueil sans que l'utilisateur aille la chercher.
- Le modèle `Insight` est générique : catégorie visuelle, micro-visuel, message court, destination. Une nouvelle source s'y branche sans toucher à l'UI de la pile.
- Formulations toujours factuelles, jamais prescriptives.

---

## Trois familles de cartes

### 1. L'alerte — toujours en premier
**Temps sous 70 mg/dL** : moyenne des trois derniers jours terminés strictement au-dessus de 3 % (`CalculAlerteTempsSousSeuil`, `ScoreService.insightTempsSousSeuil`). Rouge. Aucune destination : tout est déjà dans la carte (chiffre, trois jours, seuil).

### 2. Les cartes d'événement — du plus récent au plus ancien
Un fait vient de se produire ou de devenir consultable. Chaque carte a une **durée de vie** et s'efface seule ; la supprimer la masque pour de bon (identifiant déterministe), et un nouvel événement produit une nouvelle carte.

| Carte | Quand elle apparaît | Combien de temps | Toucher |
| ----- | ----- | ----- | ----- |
| **Repas de 14:05** (courbe) | Réponse du repas disponible (fenêtre T+4 h couverte) | 24 h après la disponibilité | Détail du repas |
| **Course de 18:30** (courbe) | Séance terminée, + 30 min d'observation, + retard capteur (3 h) | 24 h après la disponibilité | Détail de la séance |
| **Activité à importer** | Au moins une séance Apple Santé en attente d'import | Tant qu'il en reste ; change d'identifiant si l'ensemble change | Feuille d'import |
| **Charge** (« Nouvel épisode · haute · 4 jours ») | Épisode en cours ouvert depuis ≤ 7 jours, après un autre, niveau connu | 7 jours (règle partagée avec le badge de la page, `CalculEpisodesCharge.estNouvelEpisode`) | Page « Charge et glycémie » |
| **Repas à revoir** | Repas à revoir pris dans les 48 dernières heures (hors repas masqués) | 48 h après le repas | Page « Tous les repas à revoir » |
| **Ratio** (« 5 repas », moment et date du changement) | Comparaison avant/après un changement de ratio devenue calculable (5 repas depuis le changement) | 7 jours après le 5ᵉ repas | Page « Écart de ratio » |

**Cartes de courbe** (repas, séance) : aucune phrase, rien sous le graphique. La courbe est tracée entre les lignes d'hypo et d'hyper du profil (pas de bande de cible) ; un trait marque l'instant du repas, une bande la durée de l'effort. Les portions sous le seuil d'hypo sont en rouge, celles au-dessus du seuil d'hyper en orange. Le verdict n'est pas affiché : la carte montre le fait, la page de détail l'interprète. Elles se désactivent ensemble dans Profil → Repas → « Nouvelles tendances » (actives par défaut, réglage du profil synchronisé par iCloud).

### 3. Les cartes d'état — en dernier
Deux cartes qui décrivent une situation tant qu'elle dure, sans date :
- **Tendance nocturne** (B1, `AnalyseBasaleService.insightNouvelleTendance`) : verdict de la basale, sauf « pas assez de données ». Identifiant dérivé du verdict : suppression valable tant que le verdict ne change pas. Toucher → « Analyse du coucher ».
- **Écart de ratio** (R1, `AnalyseRatioService.insightEcartDetecte`) : le plus gros écart de taux de bons résultats entre tranches (seuils : 5 repas par tranche, 25 points d'écart). Une carte au plus. Toucher → « Écart de ratio ».

---

## Ordre de la pile
`CalculInsightsEvenements.ordonner` : alerte, puis événements par date décroissante (égalité départagée par l'identifiant), puis cartes d'état. Aucun plafond : la pile montre trois cartes à la fois et se parcourt en glissant vers le bas. Tout est supprimable.

Date d'un événement : instant où il devient consultable (repas : heure + 4 h ; séance : fin + 3 h 30 ; ratio : heure du 5ᵉ repas ; épisode : premier jour ; import : fin de la séance détectée).

---

## Interactions
- **Glisser vers le bas** : carte suivante (navigation cyclique), désactivé s'il n'y a qu'une carte.
- **Appui long** (0,5 s) : confirmation puis suppression. Les identifiants supprimés sont gardés en `UserDefaults` (`InsightsAccueilPersistance`) : donnée propre à l'appareil, sans enjeu à la réinstallation.
- **Toucher** : `Insight.destination` (`DestinationInsight`) décide de la page ou de la feuille ouverte. Pas de destination = pas de lien affiché à droite du titre. Le libellé du lien est celui de la carte (« Voir la réponse → », « Importer → »…), « Voir l'analyse → » par défaut.
- Aller sur la page concernée ne fait **pas** disparaître la carte.

---

## Mécanique
- `AccueilVue.insightsAffiches` est une propriété calculée, réévaluée à chaque rendu depuis les services déjà en mémoire. Les cartes de séance (une lecture du hub par séance récente) sont calculées au chargement de la page et gardées en cache d'état.
- Épisodes de charge : `CorrelationChargeTIRService` est une instance **partagée** (injectée à la racine) entre l'onglet Analyses et l'accueil. L'accueil la calcule une seule fois s'il n'y a pas encore d'épisodes ; l'onglet Analyses la rafraîchit ensuite.
- Réponse d'un repas : lue sur l'état d'analyse du repas, disponible uniquement pour les repas récents (la courbe n'est jamais persistée).
- Date de la comparaison de ratio : `ApercuChangementRatio.dateComparaisonDisponible`, heure du 5ᵉ repas depuis le changement.

---

## Couleurs
Les cartes de réponse portent chacune leur teinte (`Insight.teinte`), en plus de la catégorie : **indigo** pour un repas, **brun** pour une séance. Ni vert, jaune, orange ni rouge (réservés à la glycémie), ni violet (analyses), ni rose (confondu avec le rouge), ni turquoise (rejeté le 2026-10-21).

---

## Ce qui reste ouvert
- **Rafraîchissement dans le temps** : une carte devient visible quand la page recalcule (retour sur l'accueil), pas à la seconde où la fenêtre se ferme.
- **Tendance nocturne « en observation »** : mention proposée pour une nouvelle dose en observation, non décidée.
- **Mocks conservés mais non branchés** : `InsightsAccueilServiceMock.swift` reste pour d'éventuelles previews.
