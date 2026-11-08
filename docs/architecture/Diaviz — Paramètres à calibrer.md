# Paramètres à calibrer

>   Registre des constantes choisies par raisonnement et non par mesure. Aucune n'est une vérité physiologique : toutes attendent d'être confrontées à un historique réel.

**Statut** : 🟢 Registre vivant (2026-09-22) · **À relire** à chaque fois qu'un seuil est touché

---

## Pourquoi ce document

Les analyses de Diaviz reposent sur des dizaines de constantes — seuils, fenêtres, coefficients, minimums. Presque toutes ont été fixées **avant d'avoir des données**, par raisonnement ou par analogie avec la littérature. Elles sont plausibles, pas démontrées.

Le risque n'est pas qu'elles soient fausses : c'est qu'on **oublie qu'elles sont provisoires**. Une constante écrite dans le code depuis six mois prend l'apparence d'un fait. Ce registre existe pour qu'aucune ne se fasse oublier.

---

## Deux pièges de méthode

### Ne pas calibrer sur les données qui serviront à conclure

Ajuster la demi-vie jusqu'à maximiser la corrélation charge / TIR, puis présenter cette corrélation comme un résultat, est **circulaire**. Le paramètre aura été choisi pour produire le résultat observé.

Règle : calibrer contre une source **indépendante** de celle qui servira à conclure — le vécu rapporté, une période mise de côté, un événement connu par ailleurs. Jamais en optimisant sur la série qu'on interprétera ensuite.

### Un changement de paramètre réécrit le passé

Les analyses sont des **dérivations** calculées à la volée, jamais persistées. Changer un seuil ne modifie donc pas seulement les verdicts futurs : il **réécrit silencieusement tous les verdicts passés**. Une nuit classée « stable » hier peut devenir « tendance descendante » aujourd'hui sans qu'aucune donnée n'ait bougé.

Conséquences pratiques :

- noter **quand** et **pourquoi** un paramètre change (ce document sert aussi à ça) ;
- ne pas conclure à une évolution réelle sur une période qui chevauche un changement de paramètre ;
- se méfier du réflexe « ça a l'air mieux maintenant » juste après un ajustement de seuil.

---

## Charge active

Voir [Charge active (sport)](Diaviz%20—%20Charge%20active%20(sport).md).

| Paramètre | Valeur | Où | Statut | Comment le recalibrer |
| ----- | ----- | ----- | ----- | ----- |
| Facteurs d'intensité | faible 1,0 · modérée 2,0 · intense 3,0 | `CalculChargeActive.facteur` | 🟢 Implémenté | Comparer à une intensité dérivée de la FC moyenne quand elle est disponible |
| Intensité depuis la FC | 50 % FCmax → 1 · 70 % → 2 · 90 % → 3, borné [1, 3], FCmax personnelle | `CalculChargeActive.facteurIntensite` | 🟢 Implémenté | Les zones 50/70/90 restent théoriques ; la FCmax, elle, est observée (ligne suivante) |
| FC max personnelle | plus haut pic soutenu (médiane glissante 60 s, ≥ 3 échantillons) sur 12 mois ; séance écartée si pic > 220 ; échantillons hors 30-250 écartés | `CalculFCMax.picSoutenu`, `retenir`, `fenetreLissageSecondes`, `picPlausibleMax`, `historiqueJours` | 🟢 Implémenté | Borne basse par construction : comparer à un test d'effort maximal ou à une séance connue comme maximale |
| Repli FC max | 190 tant que < 10 séances avec pic mesurable | `CalculFCMax.fcMaxTheorique`, `seancesMinimum` | 🟢 Implémenté | La valeur observée se stabilise-t-elle avant 10 séances ? Sinon, relever le minimum |
| Seuil d'écart de niveau (entrée) | 0,4 (±40 %) | `CalculChargeActive.seuilEntreeNiveau` | 🟢 Implémenté | Le niveau annoncé correspond-il au ressenti de la semaine ? |
| Seuil de sortie (hystérésis) | 0,25 (±25 %) pour une entrée à ±40 % | `CalculChargeActive.seuilSortieNiveau` | 🟢 Implémenté | Compter les allers-retours de régime sur une série réelle |
| Jours consécutifs avant de changer de niveau | 3 | `CalculChargeActive.joursMinimumBascule` | 🟢 Implémenté | Compter les bascules jugées prématurées a posteriori |
| Fenêtre de la normale personnelle | 4 semaines glissantes, hors 7 derniers jours | `CalculChargeActive.fenetreNormaleJours` / `exclusionRecenteJours` | 🟢 Implémenté | Trop court = la normale suit la charge et l'écart s'annule ; trop long = inertie |
| Demi-vie de décroissance | 24 h | `CalculChargeActive.demiVieHeures` | 🟢 Implémenté | Confronter au vécu : combien de temps une séance isolée reste-t-elle perceptible ? |
| Amorce de l'hystérésis | 28 jours avant l'horizon, départ supposé normal | `CalculChargeActive.joursSerieNiveau` | 🟢 Implémenté | Le niveau change-t-il si on allonge l'amorce ? Sinon, 28 j suffisent |
| Préfiltre des bouts de marche | blocs de 10 min, paire voisine ≥ 1 000 pas ; plages < 3 h fusionnées | `CalculChargeActive.dureeBlocMinutes`, `ecartFusionPlagesMinutes` | 🟢 Implémenté | Performance seule : condition nécessaire, ne change aucun résultat |
| Jours relus malgré le cache des bouts | 2 | `ChargeActiveService.joursNonClos` | 🟢 Implémenté | Des pas de la montre arrivent-ils plus de 2 jours en retard ? |
| Fraîcheur des lectures Apple Santé | 15 min | `ChargeActiveService.fraicheurSante` | 🟢 Implémenté | Contrainte de performance, pas physiologique |
| Horizon du contexte partagé | 90 jours | `CalculChargeActive.horizonJours` | 🟢 Implémenté | Contrainte d'affichage (10 semaines de corrélation, 60 nuits B2/B3), pas physiologique |
| Coefficients par famille d'activité | 1,0 partout | `CalculChargeActive.coefficientType` | 🟢 Implémenté (neutre) | À différencier seulement quand le volume le permettra |
| Cadence de marche soutenue | ≥ 100 pas/min pendant ≥ 10 min consécutives | `CalculChargeActive.cadenceMarcheMin`, `dureeMarcheMinMinutes` | 🟢 Implémenté | Vérifier sur des journées dont on sait si elles comptaient comme « marche » |
| Coefficient de la marche | 0,75 | `CalculChargeActive.coefficientMarche` | 🟢 Implémenté | Une journée de marche intensive doit-elle peser autant qu'une séance faible ? |

---

## Épisodes de charge et états des réglages (C1)

Recadrage du 2026-09-27 : la « période » à vecteur de réglages constant est abandonnée, remplacée par l'épisode de charge et un état par réglage. Voir [C1 — Frise des périodes](../analyses/C1%20—%20Frise%20des%20périodes.md).

| Paramètre | Valeur | Statut | Comment le recalibrer |
| ----- | ----- | ----- | ----- |
| Frontière d'épisode | changement de niveau de charge (hystérésis de `CalculChargeActive`) | 🟡 Cadré | Les épisodes durent-ils assez pour qu'un réglage y devienne concluant ? |
| Écart de charge réelle pour « épisode comparable » | ±30 % de la moyenne du stock sur l'épisode | 🟡 Cadré | Trop large : des vies différentes mélangées. Trop étroit : jamais de comparable |
| Garde-fou hypo des états | 2 hypos ou plus dans la fenêtre → jamais concluant | 🟡 Cadré | Commun aux trois réglages. Trop strict pour le ratio sport ? |
| Lente — fenêtre / minimum / entrée / sortie | 7 nuits évaluables / 5 / 5 sur 7 / ≤ 3 sur 7 | 🟡 Cadré | Délai réel avant un état stable après un changement de dose. L'état clignote-t-il ? |
| Lente — transition après changement de dose | 2 nuits | 🟡 Cadré | Au bout de combien de nuits la dérive zone 3 se stabilise-t-elle réellement ? |
| Ratio d'un moment — fenêtre / minimum / entrée / sortie | 8 repas évaluables / 5 / 5 sur 8 / ≤ 3 sur 8 | 🟡 Cadré | Minimum aligné sur le mining R1 |
| Ratio sport — fenêtre / minimum / entrée / sortie | 6 repas du même type de sport / 4 / 4 sur 6 / ≤ 2 sur 6 | 🟡 Cadré | Proportion du temps passé en « pas assez de recul » |
| Délai entre deux changements de ratio (proposition, pas livré) | 5 repas enregistrés sur le moment ou 14 jours, au premier atteint | 🟡 Cadré (2026-11-08) | Le délai gêne-t-il un ajustement réellement nécessaire ? 5 repas enregistrés suffisent-ils, sachant que tous ne sont pas analysables ? |
| Verdict R1 `moyen` | hors compte (ni concluant ni raté) | 🟡 Cadré (2026-09-27) | Quelle part des repas tombe en `moyen` ? Si elle est forte, l'entonnoir se resserre trop |
| Résultats d'épisode — seuils de lisibilité | TIR et score : 3 jours avec CGM ; resucrages / jour : 7 jours | 🟢 Implémenté (`CalculEpisodesCharge`) | Les chiffres d'un épisode court sont-ils stables d'une semaine à l'autre ? |
| Horizon des épisodes | 90 jours (`CalculChargeActive.horizonJours`) | 🟢 Conservé (2026-10-19) | Un épisode comparable utile date-t-il de plus de 3 mois ? |
| Badge « Nouvel épisode » | 7 jours | 🟢 Implémenté (`CalculEpisodesCharge.joursNouvelEpisode`) | Ressenti de l'utilisateur |
| Jours consécutifs avant bascule de niveau | 3 (implémenté) | 🟢 Implémenté (`CalculChargeActive`) | Hérité de la charge active, plus de valeur propre à C1 |
| Fenêtre de regroupement des saisies d'un paramètre | 5 min, glissante | 🟢 Implémenté (`HistoriqueParametres.SessionsEdition.fenetreParDefaut`) | L'historique contient-il des paires de lignes rapprochées (quelques minutes) qui décrivent en fait un seul réglage ? |

----- | ----- | ----- | ----- |
| Durée de la phase de transition | 2-3 j après un changement | 🟡 Cadré | Au bout de combien de temps les résultats se stabilisent-ils réellement ? |
| Durée minimale d'une période exploitable | > durée de transition | 🟡 Cadré | Quelle proportion de périodes est écartée ? Si presque toutes, le seuil est trop haut |
| Jours consécutifs avant bascule de régime | 4-5 | 🟡 Cadré | Même mesure que `CalculChargeActive.joursMinimumBascule`, à harmoniser avec lui |
| Fenêtre de regroupement des saisies d'un paramètre | 5 min, glissante | 🟢 Implémenté (`HistoriqueParametres.SessionsEdition.fenetreParDefaut`) | L'historique contient-il des paires de lignes rapprochées (quelques minutes) qui décrivent en fait un seul réglage ? |

---

## Analyses existantes

Valeurs relevées dans la documentation et dans les messages de commit — **non revérifiées ligne à ligne dans le code** à la date de ce document.

| Paramètre | Valeur | Analyse | Comment le recalibrer |
| ----- | ----- | ----- | ----- |
| Couverture CGM minimale d'une zone | 80 % | B1 | Quelle proportion de nuits est exclue pour ce seul motif ? |
| Fenêtre de détection du phénomène de l'aube | 90 min (relevée de 45 min le 2026-09-20) | B1 | Motif du relèvement : trop sensible au bruit CGM — surveiller l'effet inverse |
| Repas minimum par tranche pour le mining | 5 | R1 | Un verdict rendu à 5 repas s'est-il révélé instable ensuite ? |
| Insuline active au début d'un repas pour l'écarter | 0,5 u (`CalculExclusionsFenetre.seuilInsulineActive`) | R1 / repas à revoir | Plus petit pas d'un stylo demi-unité, ≈ 5 g de glucides. Combien de repas sont écartés pour ce seul motif ? Si beaucoup avec un IOB juste au-dessus, vérifier d'abord la DIA du profil |
| Fenêtre d'exclusion d'un repas (autre repas, correction, resucrage, sport) | T−1 h → T+4 h, alignée sur la fenêtre du verdict | R1 / repas à revoir | Ne pas la découpler de la fenêtre du verdict : tout fait qui touche la courbe jugée doit écarter le repas |
| Occurrences minimales « repas à revoir » | 2 (réglable 1 à 5) | Carte accueil | Déjà exposé à l'utilisateur — noter les changements ici |
| Fenêtre des repas récents | 45 j | R1 / repas à revoir | Contrainte technique (courbes non persistées), pas un choix physiologique |
| DIA et pic d'action de l'insuline rapide | `diaHeures`, `picMinutes` | IOB | Paramètres du modèle Loop/OpenAPS — valeurs de référence, pas mesurées sur l'utilisateur |

---

## Journal des changements

À tenir à jour. Une ligne par modification de constante, avec sa raison.

| Date | Paramètre | Ancienne → nouvelle | Raison |
| ----- | ----- | ----- | ----- |
| 2026-09-20 | Fenêtre dawn (B1) | 45 → 90 min | Trop sensible au bruit CGM |
| 2026-09-23 | Charge active — demi-vie, marche (100 pas/min, 10 min, × 0,75), FC (50/70/90 % de 190), sortie d'hystérésis ±25 % | — → valeurs initiales | Première implémentation de `CalculChargeActive`. Entrée ±40 % et 3 jours conservés de `CalculChargeContinue` plutôt que les ±30 % / 4-5 j du cadrage |
| 2026-09-23 | Charge : paliers de séances 7 j (B2/B3) et charge continue | supprimés → niveau de charge active | Un seul calcul de charge dans l'app. Les verdicts passés de B2/B3 (pastille, critère « même charge ») changent de sens : niveaux basse/normale/haute au lieu de nombres de séances |
| 2026-09-26 | Charge active — début d'historique | plus ancienne → plus tardive des sources (pas, séances) | Normale sous-estimée avant la première séance saisie (premières semaines aberrantes). Réécrit les indices des premières semaines |
| 2026-09-26 | Charge active — indice affiché | instantané → moyenne de la journée | « normale » à côté de « +53 % » se contredisait |
| 2026-09-26 | Préfiltre des bouts de marche | heures ≥ 500 pas → blocs de 10 min (paire ≥ 1 000 pas) | Performance ; au passage, 68 bouts trouvés contre 0 : les indices de charge passés changent |
| 2026-09-26 | Charge active — FC max de l'intensité | 190 fixe → FC max observée (pic soutenu, 12 mois ; repli 190 sous 10 séances) | 190 n'était pas la FC max de l'utilisateur. **Réécrit le poids de toutes les séances passées avec FC**, donc les indices et niveaux de charge historiques (B2/B3, badges, chronologie). Même valeur pour le pré-remplissage à l'import |
| 2026-10-09 | Exclusions de fenêtre R1 (autre repas, IOB ≥ 0,5 u, correction y compris au repas, resucrage, sport) | — → valeurs initiales | Courbe d'un repas polluée par ses voisins. **Retire du mining et de « Repas à revoir » des repas déjà comptés** : verdicts de ratio et cartes peuvent changer ou repasser en « pas assez de recul » |
